// =============================================================================
// Módulo: mac_calculo
// Descrição: Multiplicador com reescala para aritmética em ponto fixo Q4.12.
//            Realiza o produto de dois operandos signed e devolve tanto o
//            produto completo (sem perda de bits) quanto o produto reescalado
//            (shift aritmético de Q_FRAC bits), mantendo os resultados no
//            formato Q4.12 após a multiplicação.
//
// Formato Q4.12:
//   - 1 bit de sinal + 3 bits inteiros + 12 bits fracionários
//   - Representação: valor_real = valor_inteiro / 2^12 (divisão por 4096)
//   - Exemplos:
//       0x1000 =  1.0     0x0800 =  0.5
//       0x0000 =  0.0     0xF000 = -1.0  (complemento de 2)
//
// Por que reescalar?
//   Ao multiplicar dois números Q4.12, o resultado tem 24 bits fracionários
//   (Q_FRAC duplica). O shift aritmético de Q_FRAC bits à direita remove os
//   bits fracionários extras e devolve o resultado no formato Q4.12 original,
//   sem overflow e sem perda da parte inteira.
//
// Parâmetros:
//   DATA_W  — largura dos operandos de entrada em bits       (padrão: 16)
//   ACC_W   — largura do acumulador / saída em bits          (padrão: 32)
//   Q_FRAC  — número de bits fracionários do formato Q4.12   (padrão: 12)
//
// Portas:
//   a              — operando A, signed, DATA_W bits
//   b              — operando B, signed, DATA_W bits
//   product_full   — produto completo a*b, ACC_W bits, sem reescala
//                    (útil para depuração ou acumulação intermediária)
//   product_scaled — produto reescalado (a*b >>> Q_FRAC), ACC_W bits,
//                    resultado em Q4.12 pronto para acumulação no MAC
//
// Uso típico no acelerador:
//   acumulador <= acumulador + produto_scaled;
//
// Observações:
//   - Módulo puramente combinacional, sem clock nem reset.
//   - O operador >>> é shift aritmético (preserva o sinal).
//   - ACC_W deve ser >= 2*DATA_W para evitar overflow no produto completo.
// =============================================================================

module mac_calculo #(
    parameter integer DATA_W = 16,
    parameter integer ACC_W  = 32,
    parameter integer Q_FRAC = 12
)(
    input  wire signed [DATA_W-1:0] a,
    input  wire signed [DATA_W-1:0] b,
    output wire signed [ACC_W-1:0]  product_full,
    output wire signed [ACC_W-1:0]  product_scaled
);

    // Produto completo (2*DATA_W bits significativos)
    // Exemplo: a=0x0800 (0.5), b=0x0800 (0.5)
    //          product_full = 0x00040000 (representando 0.25 em Q8.24)
    assign product_full = $signed(a) * $signed(b);

    // Reescala para Q4.12: remove os Q_FRAC bits fracionários extras
    // Exemplo: 0x00040000 >>> 12 = 0x00000040 = 0x0040 → 0.25 em Q4.12 ✓
    assign product_scaled = product_full >>> Q_FRAC;

endmodule