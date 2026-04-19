module elm_accel #(
    parameter integer D  = 784,
    parameter integer H  = 128,
    parameter integer C  = 10,
    parameter integer DATA_W = 16,
    parameter integer ACC_W  = 32,
    parameter integer Q_FRAC = 12,
    parameter integer CLK_HZ = 50000000,
    parameter integer STATUS_ON_SECONDS = 10,
    parameter integer IMG_BIN_TH = 1536
)(
    input  wire                  clk,
    input  wire                  reset_n,

    input  wire [31:0]           sw,
    input  wire                  confirm_btn,
    input  wire                  prep_btn,

    output wire [31:0]           result_out,

    input  wire [3:0]            avs_address,
    input  wire                  avs_write,
    input  wire [31:0]           avs_writedata,
    input  wire                  avs_read,
    output reg  [31:0]           avs_readdata,
    output wire                  avs_waitrequest,

    output wire [6:0]            hex3,
    output wire [6:0]            hex2,
    output wire [6:0]            hex1,
    output wire [6:0]            hex0,
    output wire [3:0]            ledr_pred,
    output wire [2:0]            ledr_flags
);

    assign avs_waitrequest = 1'b0;

    // =========================================================================
    // Comandos via switches
    // =========================================================================
    wire [2:0] opcode_cmd;
    wire [2:0] endereco_teste;
    wire [2:0] dado_teste;

    assign opcode_cmd     = sw[2:0];
    assign endereco_teste = sw[5:3];
    assign dado_teste     = sw[8:6];

    localparam [2:0] CMD_CLEAR_ERR = 3'd0;
    localparam [2:0] CMD_STORE_IMG = 3'd1;
    localparam [2:0] CMD_STORE_W   = 3'd2;
    localparam [2:0] CMD_STORE_B   = 3'd3;
    localparam [2:0] CMD_START     = 3'd4;
    localparam [2:0] CMD_STATUS    = 3'd5;

    // =========================================================================
    // Estados principais
    // =========================================================================
    localparam [1:0] ST_IDLE  = 2'b00;
    localparam [1:0] ST_BUSY  = 2'b01;
    localparam [1:0] ST_DONE  = 2'b10;
    localparam [1:0] ST_ERROR = 2'b11;

    // =========================================================================
    // Etapas da inferência
    // =========================================================================
    localparam [4:0] PH_H_ADDR     = 5'd0;
    localparam [4:0] PH_H_WAIT0    = 5'd1;
    localparam [4:0] PH_H_WAIT1    = 5'd2;
    localparam [4:0] PH_H_MAC      = 5'd3;
    localparam [4:0] PH_H_BIAS     = 5'd4;
    localparam [4:0] PH_H_BIAS_W0  = 5'd5;
    localparam [4:0] PH_H_BIAS_W1  = 5'd6;
    localparam [4:0] PH_H_ACT      = 5'd7;
    localparam [4:0] PH_H_SAVE     = 5'd8;
    localparam [4:0] PH_O_ADDR     = 5'd9;
    localparam [4:0] PH_O_WAIT0    = 5'd10;
    localparam [4:0] PH_O_WAIT1    = 5'd11;
    localparam [4:0] PH_O_MAC       = 5'd12;
    localparam [4:0] PH_ARGMAX_WAIT = 5'd13;
    localparam [4:0] PH_ARGMAX      = 5'd14;

    // =========================================================================
    // Detector de borda simples dos botões
    // =========================================================================
    reg confirm_d1, confirm_d2;
    reg prep_d1, prep_d2;

    wire confirma_pulso;
    wire prepara_pulso;

    assign confirma_pulso = confirm_d1 & ~confirm_d2;
    assign prepara_pulso  = prep_d1 & ~prep_d2;

    // =========================================================================
    // Estado global
    // =========================================================================
    reg [1:0] estado_atual;
    reg [2:0] comando_atual;
    reg [4:0] fase_atual;

    // =========================================================================
    // Flags de dados carregados
    // =========================================================================
    reg imagem_ok, pesos_ok, bias_ok;
    assign ledr_flags = {imagem_ok, pesos_ok, bias_ok};

    // =========================================================================
    // Predição final
    // =========================================================================
    reg [3:0] predicao_reg;
    assign ledr_pred = predicao_reg;

    // =========================================================================
    // Palavra de status
    // [3:0]   = predição
    // [4]     = busy
    // [5]     = done
    // [6]     = error
    // [7]     = bias_ok
    // [8]     = pesos_ok
    // [9]     = imagem_ok
    // [11:10] = estado
    // =========================================================================
    function [31:0] monta_resultado;
        input [1:0] st;
        input tem_img;
        input tem_peso;
        input tem_bias;
        input [3:0] pred;
        begin
            monta_resultado = 32'd0;
            monta_resultado[3:0]   = pred;
            monta_resultado[4]     = (st == ST_BUSY);
            monta_resultado[5]     = (st == ST_DONE);
            monta_resultado[6]     = (st == ST_ERROR);
            monta_resultado[7]     = tem_bias;
            monta_resultado[8]     = tem_peso;
            monta_resultado[9]     = tem_img;
            monta_resultado[11:10] = st;
        end
    endfunction

    wire [31:0] status_atual;
    assign status_atual = monta_resultado(estado_atual, imagem_ok, pesos_ok, bias_ok, predicao_reg);
    assign result_out   = status_atual;

    // Display sempre ativo
    wire        exibe_status;
    wire [31:0] palavra_status_hex;

    assign exibe_status      = 1'b1;
    assign palavra_status_hex = status_atual;

    // =========================================================================
    // Índices internos
    // =========================================================================
    reg [9:0] indice_entrada;
    reg [6:0] indice_oculto;
    reg [3:0] indice_classe;

    // =========================================================================
    // Endereços das memórias
    // =========================================================================
    reg [9:0]  endereco_img;
    reg [16:0] endereco_peso;
    reg [6:0]  endereco_bias;
    reg [10:0] endereco_beta;

    // =========================================================================
    // Dados vindos das memórias
    // =========================================================================
    wire signed [15:0] dado_img;
    wire signed [15:0] dado_peso;
    wire signed [15:0] dado_bias;
    wire signed [15:0] dado_beta;

    // =========================================================================
    // Controle de escrita nas memórias
    // =========================================================================
    reg               escreve_img, escreve_peso, escreve_bias;
    reg [9:0]         endereco_wr_img;
    reg [16:0]        endereco_wr_peso;
    reg [6:0]         endereco_wr_bias;
    reg signed [15:0] valor_wr_img;
    reg signed [15:0] valor_wr_peso;
    reg signed [15:0] valor_wr_bias;

    // =========================================================================
    // Preparação dos STOREs
    // =========================================================================
    reg               prep_img_ok;
    reg [9:0]         prep_img_addr;
    reg signed [15:0] prep_img_valor;

    reg               prep_peso_ok;
    reg [16:0]        prep_peso_addr;
    reg signed [15:0] prep_peso_valor;

    reg               prep_bias_ok;
    reg [6:0]         prep_bias_addr;
    reg signed [15:0] prep_bias_valor;

    // =========================================================================
    // Valores de teste
    // =========================================================================
    wire signed [15:0] valor_teste_img_q412;
    wire signed [15:0] valor_teste_assinado_q412;

    assign valor_teste_img_q412      = {4'd0, dado_teste, 9'd0};
    assign valor_teste_assinado_q412 = $signed({{13{dado_teste[2]}}, dado_teste}) <<< 10;

    // =========================================================================
    // Datapath
    // =========================================================================
    reg signed [ACC_W-1:0] acumulador;
    reg signed [ACC_W-1:0] soma_oculta;

    reg signed [DATA_W-1:0] h_mem [0:H-1];
    reg signed [ACC_W-1:0]  y_mem [0:C-1];

    wire signed [ACC_W-1:0] produto_oculto_full;
    wire signed [ACC_W-1:0] produto_oculto_q;
    wire signed [ACC_W-1:0] produto_saida_full;
    wire signed [ACC_W-1:0] produto_saida_q;

    wire signed [DATA_W-1:0] entrada_ativacao;
    wire signed [DATA_W-1:0] saida_ativacao;

    wire [3:0]              predicao_argmax;
    wire signed [ACC_W-1:0] maior_saida_unused;

    reg [31:0] ciclos_total;
    reg [31:0] ciclos_execucao;

    // =========================================================================
    // Endereçamento auxiliar
    // =========================================================================
    wire [16:0] base_oculta_x784;
    wire [10:0] base_oculta_x10;

    assign base_oculta_x784 = ({10'b0, indice_oculto} << 9)
                            + ({10'b0, indice_oculto} << 8)
                            + ({10'b0, indice_oculto} << 4);

    assign base_oculta_x10  = ({4'b0, indice_oculto} << 3)
                            + ({4'b0, indice_oculto} << 1);

    // =========================================================================
    // Binarização da imagem
    // =========================================================================
    wire signed [15:0] dado_img_bin;
    assign dado_img_bin = (dado_img >= IMG_BIN_TH) ? 16'sd4095 : 16'sd0;

    // =========================================================================
    // Saturação 32 -> 16 bits
    // =========================================================================
    function signed [DATA_W-1:0] sat32_to_q16;
        input signed [ACC_W-1:0] valor;
        begin
            if (valor > 32'sd32767)
                sat32_to_q16 = 16'sd32767;
            else if (valor < -32'sd32768)
                sat32_to_q16 = -16'sd32768;
            else
                sat32_to_q16 = valor[DATA_W-1:0];
        end
    endfunction

    assign entrada_ativacao = sat32_to_q16(soma_oculta);

    // =========================================================================
    // Instâncias
    // =========================================================================
    bancodememorias u_mem (
        .clk(clk),

        .endereco_img(endereco_img),
        .dado_img(dado_img),

        .endereco_peso(endereco_peso),
        .dado_peso(dado_peso),

        .endereco_bias(endereco_bias),
        .dado_bias(dado_bias),

        .endereco_beta(endereco_beta),
        .dado_beta(dado_beta),

        .escreve_img(escreve_img),
        .endereco_wr_img(endereco_wr_img),
        .valor_wr_img(valor_wr_img),

        .escreve_peso(escreve_peso),
        .endereco_wr_peso(endereco_wr_peso),
        .valor_wr_peso(valor_wr_peso),

        .escreve_bias(escreve_bias),
        .endereco_wr_bias(endereco_wr_bias),
        .valor_wr_bias(valor_wr_bias)
    );

   mac_calculo #(
    .DATA_W(DATA_W),
    .ACC_W(ACC_W),
    .Q_FRAC(Q_FRAC)
) u_mac_hidden (
    .a(dado_img),
    .b(dado_peso),
    .product_full(produto_oculto_full),
    .product_scaled(produto_oculto_q)
);

    mac_calculo #(
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .Q_FRAC(Q_FRAC)
    ) u_mac_output (
        .a(h_mem[indice_oculto]),
        .b(dado_beta),
        .product_full(produto_saida_full),
        .product_scaled(produto_saida_q)
    );

    ativacao #(
        .DATA_W(DATA_W),
        .Q_FRAC(Q_FRAC)
    ) u_ativacao (
        .entrada(entrada_ativacao),
        .saida(saida_ativacao)
    );

    argmax #(
        .ACC_W(ACC_W)
    ) u_argmax (
        .classe0(y_mem[0]), .classe1(y_mem[1]), .classe2(y_mem[2]), .classe3(y_mem[3]), .classe4(y_mem[4]),
        .classe5(y_mem[5]), .classe6(y_mem[6]), .classe7(y_mem[7]), .classe8(y_mem[8]), .classe9(y_mem[9]),
        .classe_escolhida(predicao_argmax),
        .maior_valor(maior_saida_unused)
    );

    fsm_central u_fsm (
        .habilita_display(exibe_status),
        .palavra_status(palavra_status_hex),
        .numero_predito(predicao_reg),
        .hex3(hex3),
        .hex2(hex2),
        .hex1(hex1),
        .hex0(hex0)
    );

    // =========================================================================
    // Sincronização simples dos botões
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            confirm_d1 <= 1'b0;
            confirm_d2 <= 1'b0;
            prep_d1    <= 1'b0;
            prep_d2    <= 1'b0;
        end else begin
            confirm_d1 <= confirm_btn;
            confirm_d2 <= confirm_d1;
            prep_d1    <= prep_btn;
            prep_d2    <= prep_d1;
        end
    end

    // =========================================================================
    // Preparação dos dados para STORE
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            prep_img_ok    <= 1'b0;
            prep_img_addr  <= 10'd0;
            prep_img_valor <= 16'sd0;

            prep_peso_ok    <= 1'b0;
            prep_peso_addr  <= 17'd0;
            prep_peso_valor <= 16'sd0;

            prep_bias_ok    <= 1'b0;
            prep_bias_addr  <= 7'd0;
            prep_bias_valor <= 16'sd0;
        end else begin
            if (avs_write) begin
                case (avs_address)
                    4'h0: begin
                        prep_img_ok    <= 1'b1;
                        prep_img_addr  <= avs_writedata[25:16];
                        prep_img_valor <= avs_writedata[15:0];
                    end
                    4'h1: begin
                        prep_peso_ok    <= 1'b1;
                        prep_peso_addr  <= avs_writedata[28:12];
                        prep_peso_valor <= avs_writedata[15:0];
                    end
                    4'h2: begin
                        prep_bias_ok    <= 1'b1;
                        prep_bias_addr  <= avs_writedata[22:16];
                        prep_bias_valor <= avs_writedata[15:0];
                    end
                    default: begin
                    end
                endcase
            end else if (prepara_pulso) begin
                case (opcode_cmd)
                    CMD_STORE_IMG: begin
                        prep_img_ok    <= 1'b1;
                        prep_img_addr  <= {7'd0, endereco_teste};
                        prep_img_valor <= valor_teste_img_q412;
                    end
                    CMD_STORE_W: begin
                        prep_peso_ok    <= 1'b1;
                        prep_peso_addr  <= {14'd0, endereco_teste};
                        prep_peso_valor <= valor_teste_assinado_q412;
                    end
                    CMD_STORE_B: begin
                        prep_bias_ok    <= 1'b1;
                        prep_bias_addr  <= {4'd0, endereco_teste};
                        prep_bias_valor <= valor_teste_assinado_q412;
                    end
                    default: begin
                    end
                endcase
            end else if (confirma_pulso) begin
                case (opcode_cmd)
                    CMD_STORE_IMG: if (prep_img_ok)  prep_img_ok  <= 1'b0;
                    CMD_STORE_W:   if (prep_peso_ok) prep_peso_ok <= 1'b0;
                    CMD_STORE_B:   if (prep_bias_ok) prep_bias_ok <= 1'b0;
                    default: begin
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // Escrita efetiva nas memórias
    // =========================================================================
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            escreve_img      <= 1'b0;
            escreve_peso     <= 1'b0;
            escreve_bias     <= 1'b0;
            endereco_wr_img  <= 10'd0;
            endereco_wr_peso <= 17'd0;
            endereco_wr_bias <= 7'd0;
            valor_wr_img     <= 16'sd0;
            valor_wr_peso    <= 16'sd0;
            valor_wr_bias    <= 16'sd0;
        end else begin
            escreve_img  <= 1'b0;
            escreve_peso <= 1'b0;
            escreve_bias <= 1'b0;

            if (confirma_pulso) begin
                case (opcode_cmd)
                    CMD_STORE_IMG: begin
                        if (prep_img_ok) begin
                            escreve_img      <= 1'b1;
                            endereco_wr_img  <= prep_img_addr;
                            valor_wr_img     <= prep_img_valor;
                        end
                    end
                    CMD_STORE_W: begin
                        if (prep_peso_ok) begin
                            escreve_peso      <= 1'b1;
                            endereco_wr_peso  <= prep_peso_addr;
                            valor_wr_peso     <= prep_peso_valor;
                        end
                    end
                    CMD_STORE_B: begin
                        if (prep_bias_ok) begin
                            escreve_bias      <= 1'b1;
                            endereco_wr_bias  <= prep_bias_addr;
                            valor_wr_bias     <= prep_bias_valor;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    // =========================================================================
    // FSM principal
    // =========================================================================
    integer i;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            estado_atual   <= ST_IDLE;
            comando_atual  <= CMD_CLEAR_ERR;
            fase_atual     <= PH_H_ADDR;

            imagem_ok <= 1'b0;
            pesos_ok  <= 1'b0;
            bias_ok   <= 1'b0;

            predicao_reg    <= 4'd0;
            ciclos_total    <= 32'd0;
            ciclos_execucao <= 32'd0;

            indice_entrada  <= 10'd0;
            indice_oculto   <= 7'd0;
            indice_classe   <= 4'd0;

            endereco_img    <= 10'd0;
            endereco_peso   <= 17'd0;
            endereco_bias   <= 7'd0;
            endereco_beta   <= 11'd0;

            acumulador      <= 32'sd0;
            soma_oculta     <= 32'sd0;

            for (i = 0; i < H; i = i + 1)
                h_mem[i] <= 16'sd0;

            for (i = 0; i < C; i = i + 1)
                y_mem[i] <= 32'sd0;
        end else begin
            case (estado_atual)

                ST_IDLE: begin
                    fase_atual <= PH_H_ADDR;

                    if (confirma_pulso) begin
                        case (opcode_cmd)
                            CMD_STORE_IMG: begin
                                comando_atual <= CMD_STORE_IMG;
                                estado_atual  <= ST_BUSY;
                            end
                            CMD_STORE_W: begin
                                comando_atual <= CMD_STORE_W;
                                estado_atual  <= ST_BUSY;
                            end
                            CMD_STORE_B: begin
                                comando_atual <= CMD_STORE_B;
                                estado_atual  <= ST_BUSY;
                            end
                            CMD_START: begin
                                if (imagem_ok && pesos_ok && bias_ok) begin
                                    comando_atual  <= CMD_START;
                                    estado_atual   <= ST_BUSY;

                                    fase_atual     <= PH_H_ADDR;
                                    indice_entrada <= 10'd0;
                                    indice_oculto  <= 7'd0;
                                    indice_classe  <= 4'd0;
                                    acumulador     <= 32'sd0;
                                    soma_oculta    <= 32'sd0;
                                    predicao_reg   <= 4'd0;
                                    ciclos_execucao <= 32'd0;

                                    for (i = 0; i < H; i = i + 1)
                                        h_mem[i] <= 16'sd0;

                                    for (i = 0; i < C; i = i + 1)
                                        y_mem[i] <= 32'sd0;
                                end else begin
                                    estado_atual <= ST_ERROR;
                                end
                            end
                            CMD_CLEAR_ERR: begin
                                estado_atual <= ST_IDLE;
                            end
                            CMD_STATUS: begin
                                estado_atual <= ST_IDLE;
                            end
                            default: begin
                                estado_atual <= ST_IDLE;
                            end
                        endcase
                    end
                end

                ST_BUSY: begin
                    if (comando_atual != CMD_START) begin
                        case (comando_atual)
                            CMD_STORE_IMG: imagem_ok <= 1'b1;
                            CMD_STORE_W:   pesos_ok  <= 1'b1;
                            CMD_STORE_B:   bias_ok   <= 1'b1;
                            default: begin
                            end
                        endcase

                        estado_atual <= ST_IDLE;
                    end else begin
                        ciclos_execucao <= ciclos_execucao + 32'd1;

                        case (fase_atual)
                            PH_H_ADDR: begin
                                endereco_img  <= indice_entrada;
                                endereco_peso <= base_oculta_x784 + {7'b0, indice_entrada};
                                fase_atual    <= PH_H_WAIT0;
                            end

                            PH_H_WAIT0: fase_atual <= PH_H_WAIT1;
                            PH_H_WAIT1: fase_atual <= PH_H_MAC;

                            PH_H_MAC: begin
                                acumulador <= acumulador + produto_oculto_q;

                                if (indice_entrada == D-1) begin
                                    indice_entrada <= 10'd0;
                                    fase_atual     <= PH_H_BIAS;
                                end else begin
                                    indice_entrada <= indice_entrada + 10'd1;
                                    fase_atual     <= PH_H_ADDR;
                                end
                            end

                            PH_H_BIAS: begin
                                endereco_bias <= indice_oculto;
                                fase_atual    <= PH_H_BIAS_W0;
                            end

                            PH_H_BIAS_W0: fase_atual <= PH_H_BIAS_W1;

                            PH_H_BIAS_W1: begin
                                soma_oculta <= acumulador + {{(ACC_W-DATA_W){dado_bias[DATA_W-1]}}, dado_bias};
                                fase_atual  <= PH_H_ACT;
                            end

                            PH_H_ACT: fase_atual <= PH_H_SAVE;

                            PH_H_SAVE: begin
                                h_mem[indice_oculto] <= saida_ativacao;
                                acumulador           <= 32'sd0;
                                soma_oculta          <= 32'sd0;

                                if (indice_oculto == H-1) begin
                                    indice_oculto <= 7'd0;
                                    indice_classe <= 4'd0;
                                    fase_atual    <= PH_O_ADDR;
                                end else begin
                                    indice_oculto <= indice_oculto + 7'd1;
                                    fase_atual    <= PH_H_ADDR;
                                end
                            end

                            PH_O_ADDR: begin
                                endereco_beta <= base_oculta_x10 + {7'b0, indice_classe};
                                fase_atual    <= PH_O_WAIT0;
                            end

                            PH_O_WAIT0: fase_atual <= PH_O_WAIT1;
                            PH_O_WAIT1: fase_atual <= PH_O_MAC;

                            PH_O_MAC: begin
                                if (indice_oculto == H-1) begin
                                    y_mem[indice_classe] <= acumulador + produto_saida_q;
                                    acumulador           <= 32'sd0;
                                    indice_oculto        <= 7'd0;

                                    if (indice_classe == C-1) begin
                                        indice_classe <= 4'd0;
                                        fase_atual    <= PH_ARGMAX_WAIT; // aguarda y_mem[C-1] propagar
                                    end else begin
                                        indice_classe <= indice_classe + 4'd1;
                                        fase_atual    <= PH_O_ADDR;
                                    end
                                end else begin
                                    acumulador    <= acumulador + produto_saida_q;
                                    indice_oculto <= indice_oculto + 7'd1;
                                    fase_atual    <= PH_O_ADDR;
                                end
                            end

                            PH_ARGMAX_WAIT: begin
                                fase_atual <= PH_ARGMAX;
                            end

                            PH_ARGMAX: begin
                                predicao_reg  <= predicao_argmax;
                                ciclos_total  <= ciclos_execucao + 32'd1;
                                estado_atual  <= ST_DONE;
                            end

                            default: estado_atual <= ST_ERROR;
                        endcase
                    end
                end

                ST_DONE: begin
                    if (confirma_pulso) begin
                        case (opcode_cmd)
                            CMD_CLEAR_ERR: estado_atual <= ST_IDLE;
                            CMD_STATUS:    estado_atual <= ST_DONE;
                            CMD_START: begin
                                if (imagem_ok && pesos_ok && bias_ok) begin
                                    comando_atual   <= CMD_START;
                                    estado_atual    <= ST_BUSY;

                                    fase_atual      <= PH_H_ADDR;
                                    indice_entrada  <= 10'd0;
                                    indice_oculto   <= 7'd0;
                                    indice_classe   <= 4'd0;
                                    acumulador      <= 32'sd0;
                                    soma_oculta     <= 32'sd0;
                                    predicao_reg    <= 4'd0;  // limpa predição anterior
                                    ciclos_execucao <= 32'd0;

                                    for (i = 0; i < H; i = i + 1)
                                        h_mem[i] <= 16'sd0;

                                    for (i = 0; i < C; i = i + 1)
                                        y_mem[i] <= 32'sd0;
                                end else begin
                                    estado_atual <= ST_ERROR;
                                end
                            end
                            default: estado_atual <= ST_DONE;
                        endcase
                    end
                end

                ST_ERROR: begin
                    if (confirma_pulso && (opcode_cmd == CMD_CLEAR_ERR))
                        estado_atual <= ST_IDLE;
                end

                default: estado_atual <= ST_ERROR;
            endcase
        end
    end

    // =========================================================================
    // Leitura Avalon
    // =========================================================================
    always @(*) begin
        if (avs_read) begin
            case (avs_address)
                4'h3: avs_readdata = status_atual;
                4'h4: avs_readdata = {28'd0, predicao_reg};
                4'h5: avs_readdata = ciclos_total;
                default: avs_readdata = 32'd0;
            endcase
        end else begin
            avs_readdata = 32'd0;
        end
    end

endmodule