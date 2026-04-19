// =============================================================================
// TESTBENCH COMPLETO - elm_accel (coprocessador MLP MNIST)
// =============================================================================
// Cobre:
//   1. Reset e estado inicial
//   2. CMD_STATUS via botão (sem dados)
//   3. CMD_START sem dados carregados → ST_ERROR
//   4. CMD_CLEAR_ERR → volta para ST_IDLE
//   5. CMD_STORE_IMG via botão → flag imagem_ok
//   6. CMD_STORE_W   via botão → flag pesos_ok
//   7. CMD_STORE_B   via botão → flag bias_ok
//   8. CMD_START com dados → ST_BUSY → ST_DONE → predição
//   9. Re-inferência a partir de ST_DONE
//  10. CMD_CLEAR_ERR de ST_DONE → ST_IDLE
//  11. Reset + CMD_START imediato → ST_ERROR
// =============================================================================
`timescale 1ns / 1ps

module tb_elm_accel_completo;

    // -------------------------------------------------------------------------
    // Parâmetros do DUT
    // -------------------------------------------------------------------------
    localparam integer D          = 784;
    localparam integer H          = 128;
    localparam integer C          = 10;
    localparam integer DATA_W     = 16;
    localparam integer ACC_W      = 32;
    localparam integer Q_FRAC     = 12;
    localparam integer CLK_HZ     = 50000000;
    localparam integer IMG_BIN_TH = 1536;

    // Opcodes
    localparam [2:0] CMD_CLEAR_ERR = 3'd0;
    localparam [2:0] CMD_STORE_IMG = 3'd1;
    localparam [2:0] CMD_STORE_W   = 3'd2;
    localparam [2:0] CMD_STORE_B   = 3'd3;
    localparam [2:0] CMD_START     = 3'd4;
    localparam [2:0] CMD_STATUS    = 3'd5;

    // Estados
    localparam [1:0] ST_IDLE  = 2'b00;
    localparam [1:0] ST_BUSY  = 2'b01;
    localparam [1:0] ST_DONE  = 2'b10;
    localparam [1:0] ST_ERROR = 2'b11;

    localparam CLK_PERIOD = 20; // 50 MHz

    // -------------------------------------------------------------------------
    // Sinais
    // -------------------------------------------------------------------------
    reg        clk;
    reg        reset_n;
    reg [31:0] sw;
    reg        confirm_btn;
    reg        prep_btn;

    wire [31:0] result_out;
    wire [6:0]  hex3, hex2, hex1, hex0;
    wire [3:0]  ledr_pred;
    wire [2:0]  ledr_flags;

    integer erro_count;
    integer ok_count;

    // -------------------------------------------------------------------------
    // Instância do DUT — interface Avalon desabilitada
    // -------------------------------------------------------------------------
    elm_accel #(
        .D                 (D),
        .H                 (H),
        .C                 (C),
        .DATA_W            (DATA_W),
        .ACC_W             (ACC_W),
        .Q_FRAC            (Q_FRAC),
        .CLK_HZ            (CLK_HZ),
        .STATUS_ON_SECONDS (10),
        .IMG_BIN_TH        (IMG_BIN_TH)
    ) dut (
        .clk             (clk),
        .reset_n         (reset_n),
        .sw              (sw),
        .confirm_btn     (confirm_btn),
        .prep_btn        (prep_btn),
        .result_out      (result_out),
        .avs_address     (4'd0),
        .avs_write       (1'b0),
        .avs_writedata   (32'd0),
        .avs_read        (1'b0),
        .avs_readdata    (),
        .avs_waitrequest (),
        .hex3            (hex3),
        .hex2            (hex2),
        .hex1            (hex1),
        .hex0            (hex0),
        .ledr_pred       (ledr_pred),
        .ledr_flags      (ledr_flags)
    );

    // -------------------------------------------------------------------------
    // Clock
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Tarefas auxiliares
    // -------------------------------------------------------------------------

    task wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                @(posedge clk);
        end
    endtask

    task pulso_confirm;
        begin
            @(posedge clk);
            #1 confirm_btn = 1;
            @(posedge clk);
            #1 confirm_btn = 0;
            @(posedge clk);
        end
    endtask

    task check;
        input [127:0] descricao;
        input         condicao;
        begin
            if (condicao) begin
                $display("[PASS] %s", descricao);
                ok_count = ok_count + 1;
            end else begin
                $display("[FAIL] %s  (result_out=%08h  ledr_pred=%0d  ledr_flags=%b)",
                          descricao, result_out, ledr_pred, ledr_flags);
                erro_count = erro_count + 1;
            end
        end
    endtask

    task mostra_display;
        input [127:0] label;
        begin
            $display("  [DISP %s]  HEX3=%07b HEX2=%07b HEX1=%07b HEX0=%07b",
                      label, hex3, hex2, hex1, hex0);
        end
    endtask

    // =========================================================================
    // CENÁRIO PRINCIPAL
    // =========================================================================
    initial begin
        erro_count  = 0;
        ok_count    = 0;
        reset_n     = 0;
        sw          = 32'h0;
        confirm_btn = 0;
        prep_btn    = 0;

        $display("=================================================================");
        $display("  TESTBENCH - elm_accel / coprocessador MNIST MLP");
        $display("=================================================================");

        // -------------------------------------------------------------------
        // TESTE 1 — Reset
        // -------------------------------------------------------------------
        $display("\n--- TESTE 1: Reset ativo ---");
        wait_cycles(5);
        reset_n = 1;
        wait_cycles(3);

        check("Apos reset: estado IDLE",        result_out[11:10] == ST_IDLE);
        check("Apos reset: sem imagem (bit 9=0)", result_out[9]  == 1'b0);
        check("Apos reset: sem pesos (bit 8=0)",  result_out[8]  == 1'b0);
        check("Apos reset: sem bias  (bit 7=0)",  result_out[7]  == 1'b0);
        check("Apos reset: nao em execucao",       result_out[4]  == 1'b0);
        check("Apos reset: nao finalizado",        result_out[5]  == 1'b0);
        check("Apos reset: sem erro",              result_out[6]  == 1'b0);

        mostra_display("IDLE");

        // -------------------------------------------------------------------
        // TESTE 2 — CMD_STATUS sem dados
        // -------------------------------------------------------------------
        $display("\n--- TESTE 2: CMD_STATUS via botao (sem dados) ---");
        sw = {29'd0, CMD_STATUS};
        pulso_confirm;
        wait_cycles(2);

        check("CMD_STATUS mantem ST_IDLE", result_out[11:10] == ST_IDLE);
        mostra_display("IDLE");

        // -------------------------------------------------------------------
        // TESTE 3 — CMD_START sem dados → ST_ERROR
        // -------------------------------------------------------------------
        $display("\n--- TESTE 3: CMD_START sem dados -> ST_ERROR ---");
        sw = {29'd0, CMD_START};
        pulso_confirm;
        wait_cycles(5);

        check("CMD_START sem dados -> ST_ERROR", result_out[11:10] == ST_ERROR);
        check("Flag de erro ativo (bit 6=1)",    result_out[6]     == 1'b1);

        mostra_display("ERRO");

        // -------------------------------------------------------------------
        // TESTE 4 — CMD_CLEAR_ERR → ST_IDLE
        // -------------------------------------------------------------------
        $display("\n--- TESTE 4: CMD_CLEAR_ERR -> ST_IDLE ---");
        sw = {29'd0, CMD_CLEAR_ERR};
        pulso_confirm;
        wait_cycles(3);

        check("CMD_CLEAR_ERR -> ST_IDLE",  result_out[11:10] == ST_IDLE);
        check("Flag de erro limpa (bit 6=0)", result_out[6]  == 1'b0);

        mostra_display("IDLE");

        // -------------------------------------------------------------------
        // TESTE 5 — CMD_STORE_IMG via botão → imagem_ok
        // -------------------------------------------------------------------
        $display("\n--- TESTE 5: CMD_STORE_IMG via botao ---");
        sw = {29'd0, CMD_STORE_IMG};
        pulso_confirm;
        wait_cycles(5);

        check("CMD_STORE_IMG: volta a ST_IDLE",    result_out[11:10] == ST_IDLE);
        check("Flag imagem_ok ativo (bit 9=1)",    result_out[9]     == 1'b1);
        check("LEDR_flags[2] = imagem_ok",         ledr_flags[2]     == 1'b1);

        // -------------------------------------------------------------------
        // TESTE 6 — CMD_STORE_W via botão → pesos_ok
        // -------------------------------------------------------------------
        $display("\n--- TESTE 6: CMD_STORE_W via botao ---");
        sw = {29'd0, CMD_STORE_W};
        pulso_confirm;
        wait_cycles(5);

        check("CMD_STORE_W: volta a ST_IDLE",    result_out[11:10] == ST_IDLE);
        check("Flag pesos_ok ativo (bit 8=1)",   result_out[8]     == 1'b1);
        check("LEDR_flags[1] = pesos_ok",        ledr_flags[1]     == 1'b1);

        // -------------------------------------------------------------------
        // TESTE 7 — CMD_STORE_B via botão → bias_ok
        // -------------------------------------------------------------------
        $display("\n--- TESTE 7: CMD_STORE_B via botao ---");
        sw = {29'd0, CMD_STORE_B};
        pulso_confirm;
        wait_cycles(5);

        check("CMD_STORE_B: volta a ST_IDLE",   result_out[11:10] == ST_IDLE);
        check("Flag bias_ok ativo (bit 7=1)",   result_out[7]     == 1'b1);
        check("LEDR_flags[0] = bias_ok",        ledr_flags[0]     == 1'b1);

        // -------------------------------------------------------------------
        // TESTE 8 — CMD_START com dados → inferência completa
        // -------------------------------------------------------------------
        $display("\n--- TESTE 8: CMD_START com dados -> ST_BUSY -> ST_DONE ---");
        sw = {29'd0, CMD_START};
        pulso_confirm;

        wait_cycles(3);
        check("Apos CMD_START: em ST_BUSY", result_out[11:10] == ST_BUSY);
        check("Bit busy ativo (bit 4=1)",   result_out[4]     == 1'b1);

        mostra_display("BUSY");

        begin : espera_done
            integer timeout;
            timeout = 0;
            while ((result_out[11:10] !== ST_DONE) && (timeout < 2_000_000)) begin
                @(posedge clk);
                timeout = timeout + 1;
            end
            if (timeout >= 2_000_000)
                $display("[AVISO] Timeout esperando ST_DONE!");
        end

        wait_cycles(5);

        check("Inferencia completa: ST_DONE",  result_out[11:10] == ST_DONE);
        check("Bit done ativo (bit 5=1)",      result_out[5]     == 1'b1);
        check("Bit busy inativo (bit 4=0)",    result_out[4]     == 1'b0);
        check("Predicao valida: 0 a 9",        ledr_pred         <= 4'd9);

        mostra_display("DONE");
        $display("  >>> Digito previsto = %0d <<<", ledr_pred);
        $display("  result_out = 0x%08h", result_out);

        // -------------------------------------------------------------------
        // TESTE 9 — Re-inferência a partir de ST_DONE
        // -------------------------------------------------------------------
        $display("\n--- TESTE 9: Re-inferencia a partir de ST_DONE ---");
        sw = {29'd0, CMD_START};
        pulso_confirm;

        wait_cycles(3);
        check("Apos 2 CMD_START: em ST_BUSY", result_out[11:10] == ST_BUSY);

        begin : espera_done2
            integer timeout2;
            timeout2 = 0;
            while ((result_out[11:10] !== ST_DONE) && (timeout2 < 2_000_000)) begin
                @(posedge clk);
                timeout2 = timeout2 + 1;
            end
            if (timeout2 >= 2_000_000)
                $display("[AVISO] Timeout esperando ST_DONE (2a inferencia)!");
        end

        wait_cycles(5);
        check("2a inferencia: ST_DONE",              result_out[11:10] == ST_DONE);
        check("2a predicao valida: 0 a 9",           ledr_pred         <= 4'd9);

        mostra_display("DONE2");
        $display("  >>> 2 Digito previsto = %0d <<<", ledr_pred);

        // -------------------------------------------------------------------
        // TESTE 10 — CMD_CLEAR_ERR de ST_DONE → ST_IDLE
        // -------------------------------------------------------------------
        $display("\n--- TESTE 10: CMD_CLEAR_ERR de ST_DONE -> ST_IDLE ---");
        sw = {29'd0, CMD_CLEAR_ERR};
        pulso_confirm;
        wait_cycles(3);

        check("CMD_CLEAR_ERR de ST_DONE -> ST_IDLE",      result_out[11:10] == ST_IDLE);
        check("Flags preservadas apos clear (imagem_ok=1)", result_out[9]   == 1'b1);

        mostra_display("IDLE2");

        // -------------------------------------------------------------------
        // TESTE 11 — Reset + CMD_START imediato → ST_ERROR
        // -------------------------------------------------------------------
        $display("\n--- TESTE 11: Reset + CMD_START imediato -> ST_ERROR ---");
        reset_n = 0;
        wait_cycles(3);
        reset_n = 1;
        wait_cycles(3);

        check("Apos reset: flags zeradas", result_out[9:7] == 3'b000);

        sw = {29'd0, CMD_START};
        pulso_confirm;
        wait_cycles(5);

        check("CMD_START sem flags -> ST_ERROR", result_out[11:10] == ST_ERROR);

        sw = {29'd0, CMD_CLEAR_ERR};
        pulso_confirm;
        wait_cycles(3);

        check("CMD_CLEAR_ERR limpa erro -> ST_IDLE", result_out[11:10] == ST_IDLE);

        // -------------------------------------------------------------------
        // RESULTADO FINAL
        // -------------------------------------------------------------------
        $display("\n=================================================================");
        $display("  RESULTADO FINAL: %0d PASS  /  %0d FAIL", ok_count, erro_count);
        $display("=================================================================");

        if (erro_count == 0)
            $display("  *** TODOS OS TESTES PASSARAM ***");
        else
            $display("  *** ATENCAO: %0d TESTE(S) FALHARAM ***", erro_count);

        #100;
        $stop;
    end

    // -------------------------------------------------------------------------
    // Monitor contínuo de mudanças de estado
    // -------------------------------------------------------------------------
    reg [1:0] ultimo_estado;
    initial ultimo_estado = 2'bxx;

    always @(posedge clk) begin
        if (result_out[11:10] !== ultimo_estado) begin
            ultimo_estado <= result_out[11:10];
            case (result_out[11:10])
                ST_IDLE:  $display("  [MONITOR] @ %0t ns  -> Estado: IDLE",  $time);
                ST_BUSY:  $display("  [MONITOR] @ %0t ns  -> Estado: BUSY",  $time);
                ST_DONE:  $display("  [MONITOR] @ %0t ns  -> Estado: DONE  pred=%0d", $time, result_out[3:0]);
                ST_ERROR: $display("  [MONITOR] @ %0t ns  -> Estado: ERROR", $time);
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Geração de VCD para GTKWave
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_elm_accel_completo.vcd");
        $dumpvars(0, tb_elm_accel_completo);
    end

endmodule