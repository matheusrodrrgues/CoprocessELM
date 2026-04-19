// =============================================================================
// Módulo: coprocessador — top-level da placa DE1-SoC
//
// Liga os periféricos físicos (chaves, botões, LEDs, displays) ao acelerador
// MLP. Não tem lógica própria — só conecta as duas instâncias abaixo:
//
//   inicializador  →  barramento Avalon-MM  →  elm_accel
//
// Ao soltar o reset (KEY[0]), o inicializador envia automaticamente
// STORE_IMG, STORE_W, STORE_B e START via Avalon, sem precisar mexer
// nos switches. O elm_accel processa e mostra o resultado nos displays.
//
// Mapeamento de pinos:
//   KEY[0]     reset ativo em nível baixo
//   KEY[1]     confirma comando (botão manual, ativo baixo)
//   KEY[3]     prepara dado para STORE (botão manual, ativo baixo)
//   SW[2:0]    opcode do comando
//   SW[5:3]    endereço de teste
//   SW[8:6]    valor de teste
//   LEDR[3:0]  dígito previsto em binário
//   LEDR[6:4]  flags: img_ok | peso_ok | bias_ok
//   HEX0–3     status: IDLE / BUSY / DON[dígito] / ERRO
// =============================================================================

module coprocessador (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3
);

    // SW[8:0] nos bits menos significativos; resto zerado
    wire [31:0] barramento_chaves;
    assign barramento_chaves = {23'd0, SW[8:0]};

    wire [31:0] resultado_acelerador;

    // Barramento Avalon-MM entre inicializador (mestre) e elm_accel (cria)
    wire [3:0]  avs_address;
    wire        avs_write;
    wire [31:0] avs_writedata;
    wire        avs_read;
    wire [31:0] avs_readdata;
    wire        avs_waitrequest;

    // Inicializador: ao sair do reset envia as instruções automaticamente
    inicializador u_init (
        .clk             (CLOCK_50),
        .reset_n         (KEY[0]),
        .avs_address     (avs_address),
        .avs_write       (avs_write),
        .avs_writedata   (avs_writedata),
        .avs_read        (avs_read),
        .avs_readdata    (avs_readdata),
        .avs_waitrequest (avs_waitrequest),
        .pronto          (),
        .inferencia_ok   ()
    );

    // Acelerador MLP: recebe comandos via Avalon e exibe resultado na placa
    elm_accel #(
        .CLK_HZ           (50000000),
        .STATUS_ON_SECONDS(10),
        .IMG_BIN_TH       (1536)     // limiar de binarização em Q4.12
    ) u_elm_accel (
        .clk             (CLOCK_50),
        .reset_n         (KEY[0]),
        .sw              (barramento_chaves),
        .confirm_btn     (~KEY[1]),  // KEY ativo baixo → inverte para lógica positiva
        .prep_btn        (~KEY[3]),
        .result_out      (resultado_acelerador),
        .avs_address     (avs_address),
        .avs_write       (avs_write),
        .avs_writedata   (avs_writedata),
        .avs_read        (avs_read),
        .avs_readdata    (avs_readdata),
        .avs_waitrequest (avs_waitrequest),
        .hex3            (HEX3),
        .hex2            (HEX2),
        .hex1            (HEX1),
        .hex0            (HEX0),
        .ledr_pred       (LEDR[3:0]),
        .ledr_flags      (LEDR[6:4])
    );

    assign LEDR[9:7] = 3'b000; // LEDs não usados ficam apagados

endmodule
