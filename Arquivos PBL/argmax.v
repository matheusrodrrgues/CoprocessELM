// =============================================================================
// Módulo: argmax
// Descrição: Determina qual das 10 classes da camada de saída da rede MLP
//            possui o maior valor de ativação, retornando o índice (0 a 9)
//            correspondente ao dígito previsto.
//
// Contexto na rede MLP:
//   Após calcular os 10 acumuladores y[0..9] da camada de saída, o argmax
//   aponta para o índice de maior valor — que é a predição final da rede.
//
// Algoritmo:
//   Varredura linear com atualização do máximo parcial. Começa assumindo
//   classe0 como vencedora e compara sequencialmente com classe1..classe9.
//   Em caso de empate, a classe de menor índice vence (o if usa >, não >=).
//
//   Passo 1: maior = classe0,  escolhida = 0
//   Passo 2: se classe1 > maior → maior = classe1, escolhida = 1
//   Passo 3: se classe2 > maior → maior = classe2, escolhida = 2
//   ...
//   Passo 10: se classe9 > maior → maior = classe9, escolhida = 9
//
// Parâmetros:
//   ACC_W — largura dos acumuladores de entrada em bits (padrão: 32)
//            deve ser igual ao ACC_W do elm_accel
//
// Portas:
//   classe0..classe9  — acumuladores signed da camada de saída, ACC_W bits
//                       valores em Q4.12 após o MAC da camada de saída
//   classe_escolhida  — índice da classe vencedora, 4 bits (0 a 9)
//                       conectado ao ledr_pred e ao display HEX0
//   maior_valor       — valor do acumulador vencedor, signed ACC_W bits
//                       (usado internamente pelo elm_accel; não é exibido)
//
// Observações:
//   - Módulo puramente combinacional (always @(*)), sem clock nem reset.
//   - A saída fica disponível 1 ciclo após y_mem[9] ser escrito (PH_ARGMAX_WAIT
//     no elm_accel garante esse tempo de propagação).
//   - Em caso de empate entre duas classes, a de menor índice é retornada,
//     pois as comparações usam > (estrito) e a varredura é crescente.
// =============================================================================

module argmax #(
    parameter integer ACC_W = 32
)(
    input  wire signed [ACC_W-1:0] classe0,
    input  wire signed [ACC_W-1:0] classe1,
    input  wire signed [ACC_W-1:0] classe2,
    input  wire signed [ACC_W-1:0] classe3,
    input  wire signed [ACC_W-1:0] classe4,
    input  wire signed [ACC_W-1:0] classe5,
    input  wire signed [ACC_W-1:0] classe6,
    input  wire signed [ACC_W-1:0] classe7,
    input  wire signed [ACC_W-1:0] classe8,
    input  wire signed [ACC_W-1:0] classe9,
    output reg  [3:0]              classe_escolhida,
    output reg  signed [ACC_W-1:0] maior_valor
);

    always @(*) begin
        // Passo inicial: assume classe 0 como vencedora
        classe_escolhida = 4'd0;
        maior_valor      = classe0;

        // Varredura linear: atualiza o máximo se encontrar valor maior
        if (classe1 > maior_valor) begin
            maior_valor      = classe1;
            classe_escolhida = 4'd1;
        end

        if (classe2 > maior_valor) begin
            maior_valor      = classe2;
            classe_escolhida = 4'd2;
        end

        if (classe3 > maior_valor) begin
            maior_valor      = classe3;
            classe_escolhida = 4'd3;
        end

        if (classe4 > maior_valor) begin
            maior_valor      = classe4;
            classe_escolhida = 4'd4;
        end

        if (classe5 > maior_valor) begin
            maior_valor      = classe5;
            classe_escolhida = 4'd5;
        end

        if (classe6 > maior_valor) begin
            maior_valor      = classe6;
            classe_escolhida = 4'd6;
        end

        if (classe7 > maior_valor) begin
            maior_valor      = classe7;
            classe_escolhida = 4'd7;
        end

        if (classe8 > maior_valor) begin
            maior_valor      = classe8;
            classe_escolhida = 4'd8;
        end

        if (classe9 > maior_valor) begin
            maior_valor      = classe9;
            classe_escolhida = 4'd9;
        end
    end

endmodule