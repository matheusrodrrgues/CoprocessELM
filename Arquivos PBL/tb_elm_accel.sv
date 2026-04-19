`timescale 1ns / 1ps

module tb_elm_accel;

    // Sinais de entrada
    reg         clk;
    reg         reset_n;
    reg  [2:0]  sw;
    reg         confirm_btn;

    // Sinais de saída
    wire [6:0]  hex3, hex2, hex1, hex0;
    wire [3:0]  ledr_pred;
    wire [2:0]  ledr_flags;
    wire [1:0]  current_state_out;   // 00 = DONE

    // Instancia o acelerador
    elm_accel dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .sw             (sw),
        .confirm_btn    (confirm_btn),
        .hex3           (hex3),
        .hex2           (hex2),
        .hex1           (hex1),
        .hex0           (hex0),
        .ledr_pred      (ledr_pred),
        .ledr_flags     (ledr_flags)
    );

    // Clock 50 MHz
    initial begin
        clk = 0;
        forever #10 clk = ~clk;   // período de 20 ns
    end

    initial begin
        $display("=== TESTBENCH ELM ACCELERATOR - MODELSIM ===");

        reset_n      = 0;
        sw           = 3'b000;
        confirm_btn  = 0;

        #50 reset_n = 1;

        #100;

        $display("Enviando START (sw=100 + botão)...");
        sw = 3'b100;
        #20 confirm_btn = 1;
        #40 confirm_btn = 0;

        wait (current_state_out == 2'b00);   // espera DONE

        $display("Inferência concluída!");
        $display("Dígito previsto (ledr_pred) = %d", ledr_pred);
        $display("Flags (img_ok, w_ok, b_ok)   = %b", ledr_flags);

        #200;
        $stop;
    end

endmodule