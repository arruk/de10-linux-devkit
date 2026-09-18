# IWAD shareware do Doom

O pacote do Chocolate Doom nao inclui IWAD. Para testar com o Doom shareware,
usei o arquivo `doom19s.zip` baixado em:

<https://www.dosgamesarchive.com/file/doom/doom19s/>

Depois de extrair o zip, os arquivos relevantes sao:

```text
DOOMS_19.1
DOOMS_19.2
```

Esses dois arquivos formam um instalador dividido. No Linux, junte os volumes
e extraia o IWAD com `7z`:

```bash
cd doom19s
cat DOOMS_19.1 DOOMS_19.2 > doom19s-combined.exe
mkdir -p doom19s-extracted
7z x doom19s-combined.exe -odoom19s-extracted
```

Confira se o IWAD foi gerado:

```bash
xxd -l 4 doom19s-extracted/DOOM1.WAD
```

A saida deve comecar com:

```text
IWAD
```

Use esse arquivo com o Chocolate Doom:

```bash
./run-chocolate-doom.sh -iwad /caminho/para/DOOM1.WAD
```
