# Coprocessador ELM em FPGA para Classificação de Dígitos
## MI Sistemas Digitais 2026.1 — Marco 1

## 1. Apresentação do projeto

Este repositório reúne a implementação do **Marco 1** da disciplina **MI Sistemas Digitais**, com foco no desenvolvimento de um **coprocessador em FPGA** capaz de realizar a inferência de dígitos numéricos (0 a 9) a partir de imagens do dataset MNIST.

O trabalho foi desenvolvido em grupo por:

- **Matheus Rodrigues**
- **Adna Amorim**
- **Allen Júnior**

A proposta foi construir, em hardware descrito em Verilog, uma rede neural MLP (Multi-Layer Perceptron) capaz de classificar dígitos manuscritos diretamente na FPGA, sem auxílio de processador. O sistema recebe uma imagem 28×28 pixels, processa as duas camadas da rede e retorna o dígito previsto nos displays e LEDs da placa **DE1-SoC**.

---

## 2. Objetivo

O objetivo deste marco foi implementar um núcleo de hardware capaz de:

- carregar imagem, pesos e bias via arquivos `.mif` ou via interface Avalon-MM;
- controlar o fluxo de execução por meio de uma máquina de estados;
- realizar a inferência completa da rede MLP em hardware sequencial;
- indicar o estado atual do sistema nos displays de 7 segmentos;
- retornar a predição do dígito classificado nos LEDs e no barramento de 32 bits;
- preparar a arquitetura para futura integração com um processador via Avalon-MM.

---

## 3. Levantamento de requisitos

### 3.1 Requisitos funcionais

O sistema deve:

- aceitar comandos de controle via switches/botões ou interface Avalon-MM;
- permitir o carregamento lógico de imagem, pesos e bias;
- iniciar a inferência apenas quando os três blocos estiverem confirmados;
- retornar a predição final (0 a 9);
- indicar estados IDLE, BUSY, DONE e ERROR;
- permitir leitura do resultado em barramento de 32 bits;
- funcionar localmente na placa e poder ser controlado por processador externo.

### 3.2 Requisitos de arquitetura

A solução deve possuir:

- FSM de controle com estados IDLE / BUSY / DONE / ERROR e 15 fases internas;
- duas unidades MAC para camada oculta e camada de saída;
- memórias para imagem (784×16b), pesos (100.352×16b), bias (128×16b) e beta (1.280×16b);
- função de ativação sigmoid aproximada por interpolação linear por partes;
- bloco argmax para seleção da classe final;
- suporte a reset assíncrono ativo em nível baixo;
- contagem de ciclos de execução para análise de latência.

### 3.3 Requisitos de validação

- funcionamento coerente em simulação (testbench) e em placa;
- imagens de entrada no formato Q4.12 (WIDTH=16, geradas pelo `create_img.py`);
- documentação clara da interface de controle;
- inicialização automática via módulo `inicializador.v`.

---

## 4. Softwares utilizados

| Software | Finalidade | Versão |
|---|---|---|
| Intel Quartus Prime Lite Edition | Síntese, compilação, pinagem e geração do bitstream | 25.1 |
| ModelSim / Questa Intel FPGA | Simulação e testbench | — |
| Verilog HDL | Implementação de todos os módulos | — |
| Python 3 + Pillow | Conversão de imagens PNG para `.mif` em Q4.12 | 3.x |

---

## 5. Hardware utilizado nos testes

### 5.1 Hardware principal

| Hardware | Função |
|---|---|
| DE1-SoC (Cyclone V) | Execução do projeto em FPGA |
| Cabo de programação USB | Gravação do projeto na placa |
| Computador host | Compilação, simulação e transferência |

### 5.2 Recursos da placa usados

| Pino | Sinal | Função |
|---|---|---|
| `CLOCK_50` | `clk` | Clock principal 50 MHz |
| `KEY[0]` | `reset_n` | Reset ativo em nível baixo |
| `KEY[1]` | `confirm_btn` | Confirma comando (ativo baixo) |
| `KEY[3]` | `prep_btn` | Prepara dado para STORE (ativo baixo) |
| `SW[2:0]` | `opcode_cmd` | Opcode do comando |
| `SW[5:3]` | `endereco_teste` | Endereço do dado de teste |
| `SW[8:6]` | `dado_teste` | Valor do dado de teste |
| `LEDR[3:0]` | `ledr_pred` | Predição final em binário (0–9) |
| `LEDR[6:4]` | `ledr_flags` | `[6]`=img_ok `[5]`=peso_ok `[4]`=bias_ok |
| `LEDR[9:7]` | — | Sempre apagados |
| `HEX0` | `hex0` | Dígito previsto |
| `HEX1–HEX3` | `hex1–hex3` | Status do sistema |

---

## 6. Organização dos arquivos

```
projeto/
├── coprocessador.v         ← top-level da placa
├── elm_accel.v             ← núcleo principal (FSM + datapath)
├── bancodememorias.v       ← agrupa todas as memórias
├── mac_calculo.v           ← multiplicador Q4.12
├── ativacao.v              ← sigmoid aproximada
├── argmax.v                ← seleção da classe de maior score
├── fsm_central.v           ← controlador dos displays HEX
├── inicializador.v         ← FSM de inicialização automática via Avalon
├── mem_imagem.v            ← BRAM 784×16 bits (pixels)
├── mem_pesos.v             ← BRAM 100352×16 bits (pesos W)
├── mem_bias.v              ← BRAM 128×16 bits (bias b)
├── mem_saida.v             ← ROM 1280×16 bits (pesos β)
├── W_in_q.mif              ← pesos da camada oculta em Q4.12
├── beta_q.mif              ← pesos da camada de saída em Q4.12
├── b_q.mif                 ← bias da camada oculta em Q4.12
├── create_img.py           ← converte PNG → MIF em Q4.12
└── tb_elm_accel_completo.v ← testbench completo
```

---

## 7. Visão geral da arquitetura

### 7.1 Diagrama de blocos — elm_accel

```
                        ┌─────────────────────────────────────────────────────┐
                        │                     elm_accel                       │
                        │                                                     │
  CLOCK_50 ────────────►│  ┌─────────────────────────────────────────────┐   │
  KEY[0]   ────────────►│  │         FSM + Controle                      │   │
  KEY[1]   ────────────►│  │  estado: IDLE / BUSY / DONE / ERROR         │   │
  KEY[3]   ────────────►│  │  fase:   PH_H_ADDR → PH_ARGMAX             │   │──► HEX0–HEX3
  SW[8:0]  ────────────►│  └──────────────┬──────────────────────────────┘   │──► LEDR[3:0]
                        │                 │ endereça / controla               │──► LEDR[6:4]
                        │  ┌──────────────▼──────────────┐                   │──► result_out
                        │  │      bancodememorias         │                   │
                        │  │  mem_imagem  [784 × 16b]    │                   │
                        │  │  mem_pesos   [100352 × 16b] │──pixel/peso──►    │
                        │  │  mem_bias    [128 × 16b]    │──bias────────►    │
                        │  │  mem_saida   [1280 × 16b]   │──beta────────►    │
                        │  └─────────────────────────────┘                   │
                        │                                                     │
                        │  mac_calculo ×2  →  acumulador (32b)               │
                        │  ativacao (sigmoid PWL)  →  h_mem[128]             │
                        │  y_mem[10]  →  argmax  →  predicao_reg             │
                        └─────────────────────────────────────────────────────┘
```

### 7.2 Fluxo de entradas e saídas

> Ver imagem `diagrama_de_fluxo_drawio.png` no repositório.

### 7.3 Diagrama interno do elm_accel

> Ver imagem `diagrama_drawio.png` no repositório.

---

## 8. Descrição dos módulos

### 8.1 `coprocessador.v` — Top-level

Interface entre os periféricos físicos da placa e o acelerador. Instancia o `elm_accel` e o `inicializador`, conectando os sinais Avalon entre eles. Não contém lógica própria.

### 8.2 `elm_accel.v` — Núcleo principal

É o módulo mais importante do projeto — foi onde ficou a maior parte do trabalho. Contém:

- detector de borda dos botões;
- FSM principal (IDLE / BUSY / DONE / ERROR);
- 15 fases internas de execução durante BUSY;
- controle de escrita nas memórias (STORE);
- datapath: acumulador, h_mem[128], y_mem[10];
- montagem da palavra de status de 32 bits;
- instâncias de todos os sub-módulos.

**Palavra de status `result_out[31:0]`:**

| Bits | Campo | Descrição |
|---|---|---|
| `[3:0]` | predicao | Dígito previsto (0–9) |
| `[4]` | busy | 1 quando em execução |
| `[5]` | done | 1 quando inferência concluída |
| `[6]` | error | 1 quando em estado de erro |
| `[7]` | bias_ok | Flag de bias carregado |
| `[8]` | pesos_ok | Flag de pesos carregados |
| `[9]` | imagem_ok | Flag de imagem carregada |
| `[11:10]` | estado | Estado atual (00=IDLE 01=BUSY 10=DONE 11=ERROR) |

**Registradores Avalon de leitura:**

| Endereço | Conteúdo |
|---|---|
| `0x3` | Palavra de status completa |
| `0x4` | Predição final `[3:0]` |
| `0x5` | Ciclos totais de execução |

### 8.3 `bancodememorias.v` — Banco de memórias

Agrupa as quatro memórias e gerencia o mux entre barramento de leitura (inferência) e barramento de escrita (STORE). Quando `escreve_*` está ativo, o endereço de escrita tem prioridade.

| Instância | Módulo | Tamanho | Conteúdo |
|---|---|---|---|
| `bloco_imagem` | `mem_imagem` | 784 × 16b | Pixels da entrada em Q4.12 |
| `bloco_pesos` | `mem_pesos` | 100.352 × 16b | Pesos W[784][128] da camada oculta |
| `bloco_bias` | `mem_bias` | 128 × 16b | Bias b[128] da camada oculta |
| `bloco_beta` | `mem_saida` | 1.280 × 16b | Pesos β[128][10] da camada de saída (ROM) |

### 8.4 `mac_calculo.v` — Multiplicador Q4.12

Multiplica dois operandos signed de 16 bits e reescala o resultado para manter o formato Q4.12. O shift aritmético de 12 bits (`>>> Q_FRAC`) remove os bits fracionários extras gerados pela multiplicação.

```
product_full   = a × b               (32 bits, Q8.24)
product_scaled = product_full >>> 12 (32 bits, Q4.12)
```

### 8.5 `ativacao.v` — Sigmoid aproximada

Implementa a função sigmoid por interpolação linear por partes (4 segmentos entre x = −4 e x = +4), todos em Q4.12. Fora da faixa, satura em 0 ou 4095.

Usar a sigmoid real em hardware seria inviável porque exigiria divisão e exponencial. A aproximação por trechos lineares resolve isso com apenas multiplicações e adições, mantendo erro menor que 2% na faixa útil.

| Segmento | X inicial | X final | Inclinação |
|---|---|---|---|
| 01 | −4 | −2 | 207 |
| 12 | −2 | 0 | 780 |
| 23 | 0 | +2 | 780 |
| 34 | +2 | +4 | 206 |

Fórmula: `saida = base_y + ((entrada − base_x) × inclinação) >>> 12`

### 8.6 `argmax.v` — Seleção da classe

Varredura linear comparando os 10 acumuladores `y_mem[0..9]`. Começa assumindo classe 0 como vencedora e atualiza ao encontrar valor maior. Em empate, a classe de menor índice vence (comparação estrita `>`).

### 8.7 `fsm_central.v` — Controlador dos displays

Decodifica os flags da palavra de status e exibe a mensagem correspondente nos 4 displays HEX. Prioridade: ERRO > BUSY > DON? > IDLE.

| Estado | HEX3 | HEX2 | HEX1 | HEX0 |
|---|---|---|---|---|
| ERROR | E | R | R | O |
| BUSY | B | U | S | Y |
| DONE | D | O | N | 0–9 |
| IDLE | I | D | L | E |

### 8.8 `inicializador.v` — FSM de inicialização automática

Ao sair do reset, envia automaticamente via Avalon-MM a sequência completa de instruções (`CMD_STORE_IMG` → `CMD_STORE_W` → `CMD_STORE_B` → `CMD_START`) sem necessidade de interação manual com os botões. Aguarda `ST_DONE` lendo o registrador de status.

Esse módulo foi criado para a apresentação — assim é possível demonstrar o envio completo das instruções sem precisar ficar mexendo nos switches durante a demonstração.

---

## 9. Formato numérico — Q4.12

Todo o projeto usa **ponto fixo Q4.12**:

- 16 bits totais: 1 bit de sinal + 3 bits inteiros + 12 bits fracionários
- Fator de escala: 4096 (= 2¹²)
- Exemplos: `0x1000` = 1.0 · `0x0800` = 0.5 · `0xF000` = −1.0

Usar ponto fixo foi uma decisão importante: simplifica bastante o hardware em comparação com ponto flutuante e ainda mantém precisão suficiente para a inferência funcionar corretamente.

---

## 10. Fluxo completo da inferência

```
Imagem de entrada (784 pixels, Q4.12)
           │
           ▼
┌──────────────────────────┐
│  Binarização             │  dado_img_bin = pixel >= 1536 ? 4095 : 0
│  (limiar IMG_BIN_TH)     │
└──────────┬───────────────┘
           │  pixel binarizado
           ▼
┌──────────────────────────┐
│  Camada oculta           │  repete 128 vezes (um por neurônio)
│  Para cada neurônio h:   │
│    Σ pixel[i] × W[h][i]  │  784 MACs
│    + bias[h]             │
│    → sigmoid(x)          │
│    → h_mem[h]            │
└──────────┬───────────────┘
           │  h_mem[128], Q4.12
           ▼
┌──────────────────────────┐
│  Camada de saída         │  repete 10 vezes (uma por classe)
│  Para cada classe k:     │
│    Σ h[i] × β[k][i]     │  128 MACs
│    → y_mem[k]            │
└──────────┬───────────────┘
           │  y_mem[10], Q4.12
           ▼
┌──────────────────────────┐
│  Argmax                  │  classe = índice do maior y_mem
│  classe_escolhida = 0..9 │
└──────────┬───────────────┘
           │
           ▼
    Predição final
  LEDR[3:0] + HEX0
```

---

## 11. Máquina de estados

### 11.1 Estados principais

```
         reset
           │
           ▼
        ┌──────┐
   ┌───►│ IDLE │◄────────────────────────────┐
   │    └──────┘                             │
   │       │ CMD_START                       │ CMD_CLEAR_ERR
   │       │ (flags ok)       CMD_STORE_*    │
   │       │                  ┌──────────────┘
   │       ▼                  │
   │    ┌──────┐              │
   │    │ BUSY ├──────────────┘  (STORE: 1 ciclo → IDLE)
   │    └──────┘
   │       │ inferência
   │       │ concluída
   │       ▼
   │    ┌──────┐
   └────┤ DONE │  CMD_START → BUSY
        └──────┘
           │ CMD_CLEAR_ERR
           ▼
        ┌───────┐
        │ ERROR │  CMD_CLEAR_ERR → IDLE
        └───────┘
```

### 11.2 Fases internas durante BUSY (CMD_START)

As fases existem porque as BRAMs têm latência de 2 ciclos — sem os estados de espera, o dado lido ainda não estaria disponível no ciclo do MAC.

| Fase | Nome | Descrição |
|---|---|---|
| 0 | PH_H_ADDR | Aponta endereços da imagem e do peso |
| 1–2 | PH_H_WAIT0/1 | Aguarda latência da BRAM (2 ciclos) |
| 3 | PH_H_MAC | Acumula pixel × peso |
| 4 | PH_H_BIAS | Aponta endereço do bias |
| 5–6 | PH_H_BIAS_W0/1 | Aguarda latência do bias |
| 7 | PH_H_ACT | Aplica sigmoid |
| 8 | PH_H_SAVE | Salva resultado em h_mem |
| 9 | PH_O_ADDR | Aponta endereço do beta |
| 10–11 | PH_O_WAIT0/1 | Aguarda latência da BRAM |
| 12 | PH_O_MAC | Acumula h × beta |
| 13 | PH_ARGMAX_WAIT | Aguarda propagação de y_mem[9] |
| 14 | PH_ARGMAX | Lê resultado do argmax e vai para DONE |

---

## 12. Interface de controle

### 12.1 Tabela de instruções

| Opcode | Binário | Instrução | Função |
|---|---|---|---|
| 0 | `000` | `CLEAR_ERR` | Limpa estado de erro → IDLE |
| 1 | `001` | `STORE_IMG` | Sinaliza imagem pronta (`imagem_ok = 1`) |
| 2 | `010` | `STORE_W` | Sinaliza pesos prontos (`pesos_ok = 1`) |
| 3 | `011` | `STORE_B` | Sinaliza bias pronto (`bias_ok = 1`) |
| 4 | `100` | `START` | Inicia inferência (exige as 3 flags ativas) |
| 5 | `101` | `STATUS` | Mantém estado atual (leitura de status) |

### 12.2 Modo STORE — dois comportamentos

**Com `.mif` (uso normal):** os dados já estão nas memórias desde a síntese. Os comandos STORE servem apenas para ativar as flags internas, sem regravar nada.

**Com escrita manual (teste):** é possível montar um valor pelos switches e gravá-lo na memória em duas etapas:
1. `KEY[3]` prepara o valor (opcode + endereço + dado nos switches);
2. `KEY[1]` confirma e grava.

## 13. Modo de uso na placa

### 13.1 Fluxo normal (memórias carregadas por `.mif`)

Com o `inicializador.v` instanciado, tudo acontece automaticamente ao sair do reset — nenhuma interação manual é necessária. O display mostrará:

```
IDLE → BUSY → DON[dígito]
```

### 13.2 Fluxo manual (sem o inicializador)

1. Pressionar `KEY[0]` para reset.
2. `SW[2:0] = 001` + `KEY[1]` → `STORE_IMG`
3. `SW[2:0] = 010` + `KEY[1]` → `STORE_W`
4. `SW[2:0] = 011` + `KEY[1]` → `STORE_B`
5. `SW[2:0] = 100` + `KEY[1]` → `START`
6. Aguardar display mostrar `DON[0–9]`.

### 13.3 Como limpar um erro

```
SW[2:0] = 000  +  KEY[1]  →  CLEAR_ERR
```

### 13.4 Escrita manual de teste (para depuração)

1. Configurar `SW[2:0]` = opcode, `SW[5:3]` = endereço, `SW[8:6]` = dado;
2. `KEY[3]` para preparar;
3. `KEY[1]` para gravar.

> Apertar apenas `KEY[3]` **não** grava. Apertar `KEY[1]` sem preparação também **não** grava.

---

## 14. Simulação

O testbench `tb_elm_accel_completo.v` cobre 14 cenários:

| Teste | Descrição |
|---|---|
| 1 | Reset e estado inicial |
| 2 | CMD_STATUS sem dados |
| 3 | CMD_START sem dados → ST_ERROR |
| 4 | CMD_CLEAR_ERR → ST_IDLE |
| 5–6 | Escrita de pixel via Avalon + CMD_STORE_IMG |
| 7 | Escrita de peso via Avalon + CMD_STORE_W |
| 8 | Escrita de bias via Avalon + CMD_STORE_B |
| 9 | Leitura Avalon do registrador de status (0x3) |
| 10 | CMD_START completo → ST_BUSY → ST_DONE |
| 11 | Leitura Avalon da predição (0x4) e ciclos (0x5) |
| 12 | Re-inferência a partir de ST_DONE |
| 13 | CMD_CLEAR_ERR de ST_DONE → ST_IDLE |
| 14 | Reset + CMD_START imediato → ST_ERROR |

Para rodar no ModelSim/Questasim:
```bash
vsim -c tb_elm_accel_completo -do "run -all"
```

---

## 15. Resultados observados

- Fluxo de controle funcionando corretamente em placa;
- Inferência completa executada em hardware sequencial;
- Display exibe corretamente IDLE / BUSY / DON[dígito] / ERRO;
- Predição correta para imagens geradas com `create_img.py` (Q4.12, WIDTH=16);
- Inicialização automática via `inicializador.v` funcional sem interação manual.

---

## 16. Limitações atuais

- A inferência é sequencial (não paralelizada), o que limita o throughput;
- Imagens geradas com `WIDTH=8` (uint8 bruto) não funcionam sem conversão;
- Taxa de acerto formal ainda não medida sobre o conjunto completo de teste;
- Sem comparação quantitativa com modelo de referência em software.

---

## 17. Próximos passos

- Medir taxa de acerto com o conjunto de teste completo do MNIST;
- Comparar resultados com modelo de referência em Python;
- Registrar uso de recursos (LEs, M10Ks, DSPs) no Quartus;
- Refinar a interface Avalon para integração completa com processador;
- Explorar paralelização do datapath para reduzir latência.

---

## 18. Conclusão

Este projeto mostrou que dá para fazer inferência de uma rede MLP diretamente em FPGA, sem precisar de processador. A parte mais trabalhosa foi entender e depurar o fluxo interno da FSM, principalmente os estados de espera da BRAM e a sincronização entre as fases. Outro problema que levou bastante tempo foi descobrir que as imagens de entrada precisavam estar em Q4.12 — imagens em uint8 bruto chegavam completamente pretas para a rede por causa do limiar de binarização.

No geral, a arquitetura ficou modular e organizada, o que facilita entender cada parte separadamente e também deixa o caminho aberto para a integração com processador nos próximos marcos.

