// =============================================================================
// Módulo: fsm_central
// Descrição: Controlador dos quatro displays de 7 segmentos da placa.
//            Interpreta a palavra de status do acelerador e exibe uma mensagem
//            de texto correspondente ao estado atual da inferência, além do
//            dígito previsto quando a inferência termina.
//
// Mensagens exibidas (HEX3 HEX2 HEX1 HEX0):
// ┌──────────────┬──────┬──────┬──────┬───────────────┬────────────────────┐
// │ Condição     │ HEX3 │ HEX2 │ HEX1 │ HEX0          │ palavra_status     │
// ├──────────────┼──────┼──────┼──────┼───────────────┼────────────────────┤
// │ Erro         │  E   │  R   │  R   │  O   → "ERRO" │ bit[6] = 1         │
// │ Em execução  │  B   │  U   │  S   │  Y   → "BUSY" │ bit[4] = 1         │
// │ Finalizado   │  D   │  O   │  N   │  0..9→ "DON?" │ bit[5] = 1         │
// │ Aguardando   │  I   │  D   │  L   │  E   → "IDLE" │ bits[6:4] = 000    │
// │ Desabilitado │  -   │  -   │  -   │  -   → apagado│ habilita_display=0 │
// └──────────────┴──────┴──────┴──────┴───────────────┴────────────────────┘
//
// Prioridade das mensagens (em caso de flags simultâneos):
//   1. ERRO  (maior prioridade — bit[6])
//   2. BUSY  (bit[4])
//   3. DON?  (bit[5])
//   4. IDLE  (padrão — nenhum flag ativo)
//
// Mapeamento dos bits da palavra_status:
//   bit[4] — em_execucao : acelerador processando (ST_BUSY)
//   bit[5] — finalizado  : inferência concluída   (ST_DONE)
//   bit[6] — em_erro     : erro detectado         (ST_ERROR)
//   (demais bits são ignorados por este módulo)
//
// Codificação dos segmentos (display ânodo comum, ativo em nível baixo):
//
//      ─ a ─
//   f │     │ b
//      ─ g ─
//   e │     │ c
//      ─ d ─   (ponto = dp, não usado)
//
//   Bit:  6=a 5=b 4=c 3=d 2=e 1=f 0=g   (0=segmento aceso, 1=apagado)
//
// Exemplos de codificação:
//   '0' = 7'b1000000  (segmentos a,b,c,d,e,f acesos; g apagado)
//   'E' = 7'b0000110  (segmentos a,d,e,f,g acesos)
//   ' ' = 7'b1111111  (todos apagados)
//
// Portas:
//   habilita_display — quando 0, todos os displays ficam apagados
//   palavra_status   — word de 32 bits vinda do elm_accel (result_out)
//   numero_predito   — dígito previsto (0..9), exibido no HEX0 em DON?
//   hex3..hex0       — saída para os displays de 7 segmentos
//
// Observações:
//   - Módulo puramente combinacional (always @(*)), sem clock nem reset.
//   - habilita_display está fixo em 1'b1 no elm_accel atual, portanto
//     os displays estão sempre ativos durante a operação normal.
// =============================================================================

module fsm_central (
    input  wire        habilita_display,
    input  wire [31:0] palavra_status,
    input  wire [3:0]  numero_predito,
    output reg  [6:0]  hex3,
    output reg  [6:0]  hex2,
    output reg  [6:0]  hex1,
    output reg  [6:0]  hex0
);

    // -------------------------------------------------------------------------
    // Constantes de segmentos — display ânodo comum (0 = aceso, 1 = apagado)
    // -------------------------------------------------------------------------
    localparam [6:0] DISP_APAGADO = 7'b1111111;

    localparam [6:0] LETRA_B = 7'b0000011; // B
    localparam [6:0] LETRA_U = 7'b1000001; // U
    localparam [6:0] LETRA_S = 7'b0010010; // S
    localparam [6:0] LETRA_Y = 7'b0010001; // Y

    localparam [6:0] LETRA_D = 7'b0100001; // D
    localparam [6:0] LETRA_O = 7'b1000000; // O
    localparam [6:0] LETRA_N = 7'b0101011; // N
    localparam [6:0] LETRA_E = 7'b0000110; // E

    localparam [6:0] LETRA_I = 7'b1111001; // I
    localparam [6:0] LETRA_L = 7'b1000111; // L
    localparam [6:0] LETRA_R = 7'b0101111; // R

    // -------------------------------------------------------------------------
    // Extração dos flags de estado da palavra de status
    // -------------------------------------------------------------------------
    wire em_execucao;   // bit[4]: acelerador em ST_BUSY
    wire finalizado;    // bit[5]: acelerador em ST_DONE
    wire em_erro;       // bit[6]: acelerador em ST_ERROR

    assign em_execucao = palavra_status[4];
    assign finalizado  = palavra_status[5];
    assign em_erro     = palavra_status[6];

    // -------------------------------------------------------------------------
    // Função: converte dígito (0..9) para código de 7 segmentos
    // Retorna DISP_APAGADO para valores fora do intervalo
    // -------------------------------------------------------------------------
    function [6:0] mostra_numero;
        input [3:0] valor;
        begin
            case (valor)
                4'd0: mostra_numero = 7'b1000000; // 0
                4'd1: mostra_numero = 7'b1111001; // 1
                4'd2: mostra_numero = 7'b0100100; // 2
                4'd3: mostra_numero = 7'b0110000; // 3
                4'd4: mostra_numero = 7'b0011001; // 4
                4'd5: mostra_numero = 7'b0010010; // 5
                4'd6: mostra_numero = 7'b0000010; // 6
                4'd7: mostra_numero = 7'b1111000; // 7
                4'd8: mostra_numero = 7'b0000000; // 8
                4'd9: mostra_numero = 7'b0010000; // 9
                default: mostra_numero = 7'b1111111; // apagado
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Lógica de exibição — prioridade: ERRO > BUSY > DON? > IDLE
    // -------------------------------------------------------------------------
    always @(*) begin
        // Padrão: todos os displays apagados
        hex3 = DISP_APAGADO;
        hex2 = DISP_APAGADO;
        hex1 = DISP_APAGADO;
        hex0 = DISP_APAGADO;

        if (habilita_display) begin
            if (em_erro) begin
                // "ERRO" — dado inválido ou START sem dados carregados
                hex3 = LETRA_E;
                hex2 = LETRA_R;
                hex1 = LETRA_R;
                hex0 = LETRA_O;
            end
            else if (em_execucao) begin
                // "BUSY" — inferência em andamento
                hex3 = LETRA_B;
                hex2 = LETRA_U;
                hex1 = LETRA_S;
                hex0 = LETRA_Y;
            end
            else if (finalizado) begin
                // "DON?" — inferência concluída; HEX0 mostra o dígito previsto
                hex3 = LETRA_D;
                hex2 = LETRA_O;
                hex1 = LETRA_N;
                hex0 = mostra_numero(numero_predito);
            end
            else begin
                // "IDLE" — aguardando comando
                hex3 = LETRA_I;
                hex2 = LETRA_D;
                hex1 = LETRA_L;
                hex0 = LETRA_E;
            end
        end
    end

endmodule