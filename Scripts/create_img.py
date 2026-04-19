import argparse
from PIL import Image

def converter_imagem_para_mif(caminho_imagem_entrada, caminho_arquivo_saida):
    """
    Lê uma imagem, converte para escala de cinza, redimensiona para 28x28
    e a salva como um arquivo .mif.

    Args:
        caminho_imagem_entrada (str): O caminho para a imagem de entrada.
        caminho_arquivo_saida (str): O caminho onde o arquivo .mif será salvo.
    """
    try:
        # Abre a imagem
        img = Image.open(caminho_imagem_entrada)
    except FileNotFoundError:
        print(f"Erro: O arquivo de imagem '{caminho_imagem_entrada}' não foi encontrado.")
        return

    # Converte a imagem para escala de cinza (8 bits por pixel)
    img_grayscale = img.convert('L')

    # Redimensiona a imagem para 28x28 pixels
    img_resized = img_grayscale.resize((28, 28))

    # Obtém os dados dos pixels
    pixels = list(img_resized.getdata())

    # Define a profundidade e a largura da memória para o arquivo .mif
    profundidade = 28 * 28
    largura = 8

    # Cria e escreve o conteúdo no arquivo .mif
    with open(caminho_arquivo_saida, 'w') as f:
        f.write(f'DEPTH = {profundidade};\n')
        f.write(f'WIDTH = {largura};\n')
        f.write('ADDRESS_RADIX = DEC;\n')
        f.write('DATA_RADIX = HEX;\n')
        f.write('CONTENT BEGIN\n')

        for i, pixel_value in enumerate(pixels):
            # Formata o valor do pixel em hexadecimal com dois dígitos
            hex_value = format(pixel_value, '02X')
            f.write(f'\t{i} : {hex_value};\n')

        f.write('END;\n')

    print(f"Arquivo .mif '{caminho_arquivo_saida}' gerado com sucesso!")

# Bloco principal atualizado
if __name__ == '__main__':
    # Configura o interpretador de argumentos de linha de comando
    parser = argparse.ArgumentParser(description="Converte imagens para arquivos .mif para inicialização de memória FPGA.")

    # Adiciona os argumentos obrigatórios
    parser.add_argument('entrada', type=str, help="Caminho da imagem de entrada (ex: test/5/15.png)")
    parser.add_argument('saida', type=str, help="Nome e caminho do arquivo de saída (ex: imagem_output_5.mif)")

    # Processa os argumentos digitados no terminal
    args = parser.parse_args()

    # Chama a função usando os argumentos fornecidos
    converter_imagem_para_mif(args.entrada, args.saida)
