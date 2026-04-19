module inicializador (
    input  wire        clk,
    input  wire        reset_n,

    output reg  [3:0]  avs_address,
    output reg         avs_write,
    output reg  [31:0] avs_writedata,
    output reg         avs_read,
    input  wire [31:0] avs_readdata,
    input  wire        avs_waitrequest,

    output reg         pronto,
    output reg         inferencia_ok
);

    localparam [3:0] ST_RESET     = 4'd0;
    localparam [3:0] ST_STORE_IMG = 4'd1;
    localparam [3:0] ST_WAIT_IMG  = 4'd2;
    localparam [3:0] ST_STORE_W   = 4'd3;
    localparam [3:0] ST_WAIT_W    = 4'd4;
    localparam [3:0] ST_STORE_B   = 4'd5;
    localparam [3:0] ST_WAIT_B    = 4'd6;
    localparam [3:0] ST_START     = 4'd7;
    localparam [3:0] ST_WAIT_DONE = 4'd8;
    localparam [3:0] ST_DONE      = 4'd9;

    localparam ESPERA_RESET = 10;
    reg [4:0] contador_reset;

    reg [3:0] estado;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            estado         <= ST_RESET;
            contador_reset <= 5'd0;
            avs_address    <= 4'd0;
            avs_write      <= 1'b0;
            avs_writedata  <= 32'd0;
            avs_read       <= 1'b0;
            pronto         <= 1'b0;
            inferencia_ok  <= 1'b0;
        end else begin
            avs_write <= 1'b0;
            avs_read  <= 1'b0;

            case (estado)

                // ---------------------------------------------------------
                // Aguarda estabilização após reset
                // ---------------------------------------------------------
                ST_RESET: begin
                    if (contador_reset < ESPERA_RESET)
                        contador_reset <= contador_reset + 5'd1;
                    else
                        estado <= ST_STORE_IMG;
                end

                // ---------------------------------------------------------
                // CMD_STORE_IMG — endereço 0, valor 2048 (0.5 em Q4.12)
                // avs_writedata[25:16] = endereço (10 bits)
                // avs_writedata[15:0]  = valor    (Q4.12)
                // ---------------------------------------------------------
                ST_STORE_IMG: begin
                    avs_address   <= 4'h0;
                    avs_writedata <= {6'd0, 10'd0, 16'd2048};
                    avs_write     <= 1'b1;
                    estado        <= ST_WAIT_IMG;
                end

                ST_WAIT_IMG: begin
                    if (!avs_waitrequest)
                        estado <= ST_STORE_W;
                end

                // ---------------------------------------------------------
                // CMD_STORE_W — endereço 0, valor 2048 (0.5 em Q4.12)
                // avs_writedata[28:12] = endereço (17 bits)
                // avs_writedata[15:0]  = valor    (Q4.12)
                // Atenção: bits [15:12] são compartilhados — usar valor < 4096
                // ---------------------------------------------------------
                ST_STORE_W: begin
                    avs_address   <= 4'h1;
                    avs_writedata <= {3'd0, 17'd0, 16'd2048};
                    avs_write     <= 1'b1;
                    estado        <= ST_WAIT_W;
                end

                ST_WAIT_W: begin
                    if (!avs_waitrequest)
                        estado <= ST_STORE_B;
                end

                // ---------------------------------------------------------
                // CMD_STORE_B — endereço 0, valor 1024 (0.25 em Q4.12)
                // avs_writedata[22:16] = endereço (7 bits)
                // avs_writedata[15:0]  = valor    (Q4.12)
                // ---------------------------------------------------------
                ST_STORE_B: begin
                    avs_address   <= 4'h2;
                    avs_writedata <= {9'd0, 7'd0, 16'd1024};
                    avs_write     <= 1'b1;
                    estado        <= ST_WAIT_B;
                end

                ST_WAIT_B: begin
                    if (!avs_waitrequest)
                        estado <= ST_START;
                end

                // ---------------------------------------------------------
                // CMD_START — dispara inferência (endereço 0xF, opcode 4)
                // Só chega aqui se imagem_ok/pesos_ok/bias_ok já estão
                // setados pelos STOREs anteriores dentro do elm_accel
                // ---------------------------------------------------------
                ST_START: begin
                    avs_address   <= 4'hF;
                    avs_writedata <= 32'd4;
                    avs_write     <= 1'b1;
                    pronto        <= 1'b1;
                    estado        <= ST_WAIT_DONE;
                end

                // ---------------------------------------------------------
                // Aguarda ST_DONE: lê registrador de status (endereço 0x3)
                // bit[5] = 1 indica inferência concluída
                // ---------------------------------------------------------
                ST_WAIT_DONE: begin
                    avs_address <= 4'h3;
                    avs_read    <= 1'b1;
                    if (avs_readdata[5] == 1'b1)
                        estado <= ST_DONE;
                end

                // ---------------------------------------------------------
                // Inferência concluída — trava aqui até próximo reset
                // ---------------------------------------------------------
                ST_DONE: begin
                    inferencia_ok <= 1'b1;
                    avs_read      <= 1'b0;
                end

                default: estado <= ST_RESET;

            endcase
        end
    end

endmodule