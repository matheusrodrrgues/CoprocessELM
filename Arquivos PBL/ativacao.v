// =============================================================================
// Módulo: ativacao
// Descrição: Função de ativação sigmoid aproximada por interpolação linear
//            por partes (piecewise linear), operando em ponto fixo Q4.12.
//            Usada na camada oculta da rede MLP após o cálculo do MAC + bias.
//
// Por que aproximar a sigmoid?
//   A sigmoid real σ(x) = 1/(1+e^(-x)) exige divisão e exponencial, operações
//   custosas em hardware. A aproximação linear por partes é implementável com
//   apenas multiplicações e adições, mantendo erro < 2% na faixa útil.
//
//
// Tabela de pontos de controle (todos em Q4.12, fator de escala = 4096):
// ┌──────┬──────────────┬──────────────┬────────────────────────────────────┐
// │ Ponto│ X real       │ X Q4.12      │ Y Q4.12  (sigmoid(X) × 4096)      │
// ├──────┼──────────────┼──────────────┼────────────────────────────────────┤
// │ PX0  │    -4        │  -16384      │    74   (σ(-4) ≈ 0.018)            │
// │ PX1  │    -2        │   -8192      │   488   (σ(-2) ≈ 0.119)            │
// │ PX2  │     0        │       0      │  2048   (σ( 0) = 0.500)            │
// │ PX3  │    +2        │    8192      │  3608   (σ(+2) ≈ 0.881)            │
// │ PX4  │    +4        │   16384      │  4021   (σ(+4) ≈ 0.982)            │
// └──────┴──────────────┴──────────────┴────────────────────────────────────┘
//
// Inclinações por segmento (slope = ΔY/ΔX, em Q4.12):
// ┌──────────┬──────────────────────────────────────────────────────────────┐
// │ Segmento │ Cálculo                                                      │
// ├──────────┼──────────────────────────────────────────────────────────────┤
// │ INC_01   │ (488  -   74) / (8192×2) × 4096 = 414/2 = 207               │
// │ INC_12   │ (2048 -  488) / (8192×2) × 4096 = 1560/2 = 780              │
// │ INC_23   │ (3608 - 2048) / (8192×2) × 4096 = 1560/2 = 780              │
// │ INC_34   │ (4021 - 3608) / (8192×2) × 4096 = 413/2 ≈ 206               │
// └──────────┴──────────────────────────────────────────────────────────────┘
//
// Fórmula de interpolação para cada segmento:
//   saida = base_y + ((entrada - base_x) × inclinacao) >>> Q_FRAC
//
// Saturação:
//   entrada ≤ -4  →  saida = 0     (LIMITE_MIN)
//   entrada ≥ +4  →  saida = 4095  (LIMITE_MAX)
//   resultado fora de [0, 4095] após interpolação → satura nos limites
//
// Parâmetros:
//   DATA_W — largura dos dados em bits    (padrão: 16)
//   Q_FRAC — bits fracionários do Q4.12   (padrão: 12)
//
// Portas:
//   entrada — valor pré-ativação (soma_oculta saturada), signed Q4.12
//   saida   — valor pós-ativação σ(entrada), signed Q4.12, range [0, 4095]
//
// Observações:
//   - Módulo puramente combinacional (always @(*)), sem clock nem reset.
//   - A saída está sempre no range [0, 4095], ou seja, sempre não-negativa,
//     o que é consistente com a sigmoid real (range (0,1)).
//   - interp usa 32 bits para evitar overflow na multiplicação intermediária
//     (delta_x × inclinacao pode chegar a 16 bits × 16 bits = 32 bits).
// =============================================================================

module ativacao #(
    parameter integer DATA_W = 16,
    parameter integer Q_FRAC = 12
)(
    input  wire signed [DATA_W-1:0] entrada,
    output reg  signed [DATA_W-1:0] saida
);

    // -------------------------------------------------------------------------
    // Limites de saturação da saída em Q4.12
    // -------------------------------------------------------------------------
    localparam signed [15:0] LIMITE_MIN = 16'sd0;      // σ → 0 quando x → -∞
    localparam signed [15:0] LIMITE_MAX = 16'sd4095;   // σ → 1 quando x → +∞

    // -------------------------------------------------------------------------
    // Pontos de controle no eixo X em Q4.12 (valor_real × 4096)
    // -------------------------------------------------------------------------
    localparam signed [15:0] PX0 = -16'sd16384; // x = -4
    localparam signed [15:0] PX1 = -16'sd8192;  // x = -2
    localparam signed [15:0] PX2 =  16'sd0;     // x =  0
    localparam signed [15:0] PX3 =  16'sd8192;  // x = +2
    localparam signed [15:0] PX4 =  16'sd16384; // x = +4

    // -------------------------------------------------------------------------
    // Valores da sigmoid nos pontos de controle em Q4.12 (sigmoid(x) × 4096)
    // -------------------------------------------------------------------------
    localparam signed [15:0] PY0 = 16'sd74;    // σ(-4) ≈ 0.018
    localparam signed [15:0] PY1 = 16'sd488;   // σ(-2) ≈ 0.119
    localparam signed [15:0] PY2 = 16'sd2048;  // σ( 0) = 0.500
    localparam signed [15:0] PY3 = 16'sd3608;  // σ(+2) ≈ 0.881
    localparam signed [15:0] PY4 = 16'sd4021;  // σ(+4) ≈ 0.982

    // -------------------------------------------------------------------------
    // Inclinações de cada segmento em Q4.12 (ΔY/ΔX × 4096)
    // -------------------------------------------------------------------------
    localparam signed [15:0] INC_01 = 16'sd207; // segmento [-4, -2]
    localparam signed [15:0] INC_12 = 16'sd780; // segmento [-2,  0]
    localparam signed [15:0] INC_23 = 16'sd780; // segmento [ 0, +2]
    localparam signed [15:0] INC_34 = 16'sd206; // segmento [+2, +4]

    // -------------------------------------------------------------------------
    // Variáveis internas do bloco combinacional
    // -------------------------------------------------------------------------
    reg signed [15:0] base_x;      // X do ponto inicial do segmento ativo
    reg signed [15:0] base_y;      // Y do ponto inicial do segmento ativo
    reg signed [15:0] inclinacao;  // slope do segmento ativo
    reg signed [31:0] delta_x;     // distância da entrada até base_x
    reg signed [31:0] interp;      // resultado intermediário da interpolação

    // -------------------------------------------------------------------------
    // Lógica combinacional: seleção de segmento + interpolação + saturação
    // -------------------------------------------------------------------------
    always @(*) begin
        // Valores padrão (evita latch em síntese)
        base_x     = PX0;
        base_y     = PY0;
        inclinacao = INC_01;
        delta_x    = 32'sd0;
        interp     = 32'sd0;
        saida      = 16'sd0;

        if (entrada <= PX0) begin
            // Fora da faixa à esquerda: satura no mínimo
            saida = LIMITE_MIN;
        end
        else if (entrada >= PX4) begin
            // Fora da faixa à direita: satura no máximo
            saida = LIMITE_MAX;
        end
        else begin
            // Seleciona o segmento linear correspondente à entrada
            if (entrada < PX1) begin
                base_x     = PX0; base_y = PY0; inclinacao = INC_01;
            end
            else if (entrada < PX2) begin
                base_x     = PX1; base_y = PY1; inclinacao = INC_12;
            end
            else if (entrada < PX3) begin
                base_x     = PX2; base_y = PY2; inclinacao = INC_23;
            end
            else begin
                base_x     = PX3; base_y = PY3; inclinacao = INC_34;
            end

            // Interpolação linear: saida = base_y + (Δx × slope) >> Q_FRAC
            delta_x = entrada - base_x;
            interp  = (delta_x * inclinacao) >>> Q_FRAC;
            saida   = base_y + interp[15:0];

            // Saturação final (cobre imprecisões de arredondamento nos extremos)
            if (saida > LIMITE_MAX)
                saida = LIMITE_MAX;
            else if (saida < LIMITE_MIN)
                saida = LIMITE_MIN;
        end
    end

endmodule