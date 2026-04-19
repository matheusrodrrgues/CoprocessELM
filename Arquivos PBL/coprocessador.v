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

    // -----------------------------------------------------------------
    // Barramento de chaves (apenas SW[8:0] usados)
    // -----------------------------------------------------------------
    wire [31:0] barramento_chaves;
    assign barramento_chaves = {23'd0, SW[8:0]};

    wire [31:0] resultado_acelerador;

    // -----------------------------------------------------------------
    // Fios do barramento Avalon-MM entre inicializador (mestre)
    // e elm_accel (escravo)
    // -----------------------------------------------------------------
    wire [3:0]  avs_address;
    wire        avs_write;
    wire [31:0] avs_writedata;
    wire        avs_read;
    wire [31:0] avs_readdata;
    wire        avs_waitrequest;

    // -----------------------------------------------------------------
    // Instância do inicializador (mestre Avalon)
    // -----------------------------------------------------------------
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

    // -----------------------------------------------------------------
    // Instância do acelerador MLP (escravo Avalon)
    // -----------------------------------------------------------------
    elm_accel #(
        .CLK_HZ           (50000000),
        .STATUS_ON_SECONDS(10),
        .IMG_BIN_TH       (1536)
    ) u_elm_accel (
        .clk             (CLOCK_50),
        .reset_n         (KEY[0]),

        .sw              (barramento_chaves),
        .confirm_btn     (~KEY[1]),
        .prep_btn        (~KEY[3]),

        .result_out      (resultado_acelerador),

        // Avalon-MM conectado ao inicializador
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

    assign LEDR[9:7] = 3'b000;

endmodule