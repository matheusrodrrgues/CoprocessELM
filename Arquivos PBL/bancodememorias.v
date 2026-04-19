// =============================================================================
// Módulo: bancodememorias
// Descrição: Concentra todas as memórias do acelerador MLP em um único módulo,
//            simplificando o roteamento de sinais no elm_accel. Gerencia o
//            chaveamento entre o barramento de leitura (inferência) e o
//            barramento de escrita (carga de dados), garantindo que a escrita
//            tenha prioridade sobre a leitura quando ativa.
//
// Memórias instanciadas:
// ┌────────────────┬───────────┬──────────┬──────────┬────────────────────────┐
// │ Instância      │ Módulo    │ Endereço │ Palavras │ Conteúdo               │
// ├────────────────┼───────────┼──────────┼──────────┼────────────────────────┤
// │ bloco_imagem   │ mem_imagem│ 10 bits  │ 784      │ Pixels da entrada      │
// │                │           │          │ (28×28)  │ em Q4.12, signed 16b   │
// ├────────────────┼───────────┼──────────┼──────────┼────────────────────────┤
// │ bloco_pesos    │ mem_pesos │ 17 bits  │ 100.352  │ Pesos W da camada      │
// │                │           │          │ (784×128)│ oculta, Q4.12          │
// ├────────────────┼───────────┼──────────┼──────────┼────────────────────────┤
// │ bloco_bias     │ mem_bias  │  7 bits  │ 128      │ Bias b da camada       │
// │                │           │          │          │ oculta, Q4.12          │
// ├────────────────┼───────────┼──────────┼──────────┼────────────────────────┤
// │ bloco_beta     │ mem_saida │ 11 bits  │ 1.280    │ Pesos β da camada de   │
// │                │           │          │ (128×10) │ saída, somente leitura │
// └────────────────┴───────────┴──────────┴──────────┴────────────────────────┘
//
// Chaveamento de endereço (leitura × escrita):
//   Cada memória com suporte a escrita possui dois barramentos de endereço:
//     - endereco_*     : usado pelo acelerador durante a inferência (leitura)
//     - endereco_wr_*  : usado pelo controlador durante a carga de dados
//   Quando o sinal escreve_* está ativo, o mux seleciona o endereço de escrita,
//   bloqueando temporariamente o endereço de leitura. Isso é seguro pois a
//   inferência só ocorre após todos os dados estarem carregados (flags ok).
//
//   Esquema do mux para cada memória gravável:
//
//   escreve_* ──┐
//               ▼
//   endereco_wr_* ──[1]──┐
//                         ├──► endereco_final_* ──► memória
//   endereco_*   ──[0]──┘
//
// Portas — Leitura (inferência):
//   clk              — clock síncrono (todas as memórias são síncronas)
//   endereco_img     — endereço de leitura da imagem     [9:0]  (0..783)
//   dado_img         — pixel lido, signed Q4.12          [15:0]
//   endereco_peso    — endereço de leitura do peso       [16:0] (0..100351)
//   dado_peso        — peso lido, signed Q4.12           [15:0]
//   endereco_bias    — endereço de leitura do bias       [6:0]  (0..127)
//   dado_bias        — bias lido, signed Q4.12           [15:0]
//   endereco_beta    — endereço de leitura do beta       [10:0] (0..1279)
//   dado_beta        — peso beta lido, signed Q4.12      [15:0]
//
// Portas — Escrita (carga de dados):
//   escreve_img      — habilita escrita na mem_imagem
//   endereco_wr_img  — endereço de escrita               [9:0]
//   valor_wr_img     — valor a gravar, signed Q4.12      [15:0]
//   escreve_peso     — habilita escrita na mem_pesos
//   endereco_wr_peso — endereço de escrita               [16:0]
//   valor_wr_peso    — valor a gravar, signed Q4.12      [15:0]
//   escreve_bias     — habilita escrita na mem_bias
//   endereco_wr_bias — endereço de escrita               [6:0]
//   valor_wr_bias    — valor a gravar, signed Q4.12      [15:0]
//
// Observações:
//   - mem_saida (bloco_beta) é somente leitura: inicializada via arquivo .mif
//     em síntese e não possui porta de escrita.
//   - A latência de leitura de todas as memórias é de 1 ciclo de clock
//     (memórias síncronas do tipo altsyncram).
//   - Não há lógica sequencial neste módulo além das próprias memórias.
// =============================================================================

module bancodememorias (
    input  wire                  clk,

    // --- Leitura (inferência) ------------------------------------------------
    input  wire [9:0]            endereco_img,
    output wire signed [15:0]    dado_img,

    input  wire [16:0]           endereco_peso,
    output wire signed [15:0]    dado_peso,

    input  wire [6:0]            endereco_bias,
    output wire signed [15:0]    dado_bias,

    input  wire [10:0]           endereco_beta,     // somente leitura
    output wire signed [15:0]    dado_beta,

    // --- Escrita (carga de dados) --------------------------------------------
    input  wire                  escreve_img,
    input  wire [9:0]            endereco_wr_img,
    input  wire signed [15:0]    valor_wr_img,

    input  wire                  escreve_peso,
    input  wire [16:0]           endereco_wr_peso,
    input  wire signed [15:0]    valor_wr_peso,

    input  wire                  escreve_bias,
    input  wire [6:0]            endereco_wr_bias,
    input  wire signed [15:0]    valor_wr_bias
);

    // -------------------------------------------------------------------------
    // Mux de endereços: escrita tem prioridade sobre leitura
    // -------------------------------------------------------------------------
    wire [9:0]  endereco_final_img;
    wire [16:0] endereco_final_peso;
    wire [6:0]  endereco_final_bias;

    assign endereco_final_img  = escreve_img  ? endereco_wr_img  : endereco_img;
    assign endereco_final_peso = escreve_peso ? endereco_wr_peso : endereco_peso;
    assign endereco_final_bias = escreve_bias ? endereco_wr_bias : endereco_bias;

    // -------------------------------------------------------------------------
    // Memória da imagem — 784 palavras × 16 bits, leitura/escrita
    // Inicializada com a imagem de entrada antes da inferência
    // -------------------------------------------------------------------------
    mem_imagem bloco_imagem (
        .clock   (clk),
        .address (endereco_final_img),
        .data    (valor_wr_img),
        .wren    (escreve_img),
        .q       (dado_img)
    );

    // -------------------------------------------------------------------------
    // Memória de pesos W — 100.352 palavras × 16 bits, leitura/escrita
    // Matriz W[784][128] da camada oculta, armazenada linearmente:
    //   endereço = neurônio_oculto * 784 + pixel
    // -------------------------------------------------------------------------
    mem_pesos bloco_pesos (
        .clock   (clk),
        .address (endereco_final_peso),
        .data    (valor_wr_peso),
        .wren    (escreve_peso),
        .q       (dado_peso)
    );

    // -------------------------------------------------------------------------
    // Memória de bias b — 128 palavras × 16 bits, leitura/escrita
    // Um bias por neurônio da camada oculta
    // -------------------------------------------------------------------------
    mem_bias bloco_bias (
        .clock   (clk),
        .address (endereco_final_bias),
        .data    (valor_wr_bias),
        .wren    (escreve_bias),
        .q       (dado_bias)
    );

    // -------------------------------------------------------------------------
    // Memória de pesos β (saída) — 1.280 palavras × 16 bits, somente leitura
    // Matriz β[128][10] da camada de saída, inicializada via .mif em síntese
    //   endereço = neurônio_oculto * 10 + classe
    // -------------------------------------------------------------------------
    mem_saida bloco_beta (
        .clock   (clk),
        .address (endereco_beta),
        .q       (dado_beta)
    );

endmodule