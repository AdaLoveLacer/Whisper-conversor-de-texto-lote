# Verifica se o ffmpeg esta disponivel no PATH
function Test-FFmpeg {
    $ffmpeg = Get-Command ffmpeg -ErrorAction SilentlyContinue
    if (-not $ffmpeg) {
        Write-Host "Erro: ffmpeg nao encontrado no PATH do sistema. Instale o ffmpeg e adicione ao PATH." -ForegroundColor Red
        return
    }
}

# Caminho do arquivo de progresso
$progressFile = "F:\Whisper\progresso_segmentos.txt"

# Funcao para ler progresso salvo
function Get-ProgressoSegmentos {
    if (Test-Path $progressFile) {
        $lines = Get-Content $progressFile
        $info = @{}
        foreach ($line in $lines) {
            if ($line -match "^dir:(.+)$") { $info.dir = $Matches[1].Trim() }
            elseif ($line -match "^segmento:(.+)$") { $info.segmento = $Matches[1].Trim() }
        }
        return $info
    }
    return $null
}

# Funcao para salvar progresso
function Save-ProgressoSegmentos($dir, $segmento) {
    $progressDir = Split-Path $progressFile
    if (!(Test-Path -Path $progressDir)) {
        New-Item -ItemType Directory -Path $progressDir -Force | Out-Null
    }
    Set-Content -Encoding UTF8 $progressFile "dir:$dir`nsegmento:$segmento"
}

# Funcao para remover progresso
function Remove-ProgressoSegmentos {
    if (Test-Path $progressFile) { Remove-Item $progressFile }
}

# Checa progresso de segmentos
$progresso = Get-ProgressoSegmentos
if ($progresso) {
    Write-Host "Progresso anterior detectado!"
    Write-Host "Diretorio dos segmentos: $($progresso.dir)"
    Write-Host "Ultimo segmento processado: $($progresso.segmento)"
    $resposta = Read-Host "Deseja continuar do ultimo segmento? (S para continuar / qualquer tecla para comecar do zero)"
    if ($resposta -notmatch "^[Ss]$") {
        Remove-ProgressoSegmentos
        $progresso = $null
    }
}

function Start-VideosProcessing {
    # Definicao do diretorio de saida para os arquivos processados (edite esse valor conforme desejar)
    $outputDirectory = "F:\Whisper\Videos-processados"

    # Cria o diretorio de saida, se nao existir
    if (!(Test-Path -Path $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }

    # Solicita ao usuario o caminho do diretorio contendo os videos
    $videoDir = Read-Host "Informe o caminho do diretorio contendo os videos"

    # Garante que o diretorio esteja entre aspas
    if (-not ($videoDir.StartsWith('"') -and $videoDir.EndsWith('"'))) {
        $videoDir = '"' + $videoDir.Trim('"') + '"'
    }

    # Remove as aspas para uso interno do PowerShell (pois Test-Path e Get-ChildItem nao precisam delas)
    $videoDirUnquoted = $videoDir.Trim('"')

    # Obtem o nome da ultima pasta do diretorio de origem
    $sourceFolderName = Split-Path $videoDirUnquoted -Leaf

    # Define o diretorio de saida especifico para este lote
    $outputSubDirectory = Join-Path $outputDirectory $sourceFolderName

    # Cria o diretorio de saida do lote, se nao existir
    if (!(Test-Path -Path $outputSubDirectory)) {
        New-Item -ItemType Directory -Path $outputSubDirectory | Out-Null
    }

    # Verifica se o diretorio informado existe
    if (!(Test-Path -Path $videoDirUnquoted)) {
        Write-Host "O diretorio informado nao existe." -ForegroundColor Red
        return
    }

    # Pergunta ao usuario se deseja processar video ou audio
    Write-Host "Deseja processar arquivos de video ou audio?"
    Write-Host "1 - Video (.mp4, .mkv)"
    Write-Host "2 - Audio (.mp3, .wav)"
    do {
        $tipoArquivo = Read-Host "Escolha 1 para video ou 2 para audio"
        $isValidTipo = $tipoArquivo -eq "1" -or $tipoArquivo -eq "2"
        if (-not $isValidTipo) { Write-Host "Opcao invalida. Tente novamente." -ForegroundColor Red }
    } while (-not $isValidTipo)

    # Define extensoes conforme escolha
    if ($tipoArquivo -eq "1") {
        $extensoes = @("*.mp4", "*.mkv")
    } else {
        $extensoes = @("*.mp3", "*.wav")
    }

    # Obtem todos os arquivos no diretorio especificado conforme extensoes
    $arquivos = @()
    foreach ($ext in $extensoes) {
        $arquivos += Get-ChildItem -Path $videoDirUnquoted -Filter $ext
    }

    # Verifica se ha arquivos no diretorio
    if ($arquivos.Count -eq 0) {
        Write-Host "Nenhum arquivo encontrado no diretorio $videoDir com as extensoes selecionadas." -ForegroundColor Red
        return
    }

    # Pergunta ao usuario quantos arquivos deseja processar
    $totalArquivos = $arquivos.Count

    # Exibe a lista de arquivos encontrados com indice
    Write-Host "Arquivos encontrados:"
    for ($i = 0; $i -lt $totalArquivos; $i++) {
        Write-Host "$($i+1): $($arquivos[$i].Name)"
    }

    # Permite ao usuario escolher qualquer quantidade de arquivos ou todos
    do {
        $userInput = Read-Host "Digite os numeros dos arquivos desejados separados por virgula (ex: 1,3,4) ou 'todos' para processar todos"
        $userInput = $userInput.Trim()
        if ($userInput.ToLower() -eq "todos") {
            $arquivosSelecionados = $arquivos
            $isValidSel = $true
        } else {
            $indices = $userInput -split "," | ForEach-Object { $_.Trim() }
            $isValidSel = $indices.Count -ge 1 -and $indices.Count -le $totalArquivos -and ($indices | ForEach-Object { ($_ -as [int]) -and ($_ -ge 1) -and ($_ -le $totalArquivos) }) -notcontains $false
            if ($isValidSel) {
                $arquivosSelecionados = @()
                foreach ($idx in $indices) {
                    $arquivosSelecionados += $arquivos[$idx-1]
                }
            }
        }
        if (-not $isValidSel) {
            Write-Host "Selecao invalida. Digite os numeros validos separados por virgula ou 'todos'." -ForegroundColor Red
        }
    } while (-not $isValidSel)
    $arquivos = $arquivosSelecionados

    # Pergunta ao usuario qual modelo deseja utilizar
    $modelOptions = @("tiny", "base", "small", "medium", "large")
    Write-Host "Selecione o modelo do Whisper:"
    for ($i = 0; $i -lt $modelOptions.Count; $i++) {
        Write-Host "$($i+1) - $($modelOptions[$i])"
    }
    do {
        $modelChoice = Read-Host "Digite o numero correspondente ao modelo desejado"
        $isValid = ($modelChoice -as [int]) -and ($modelChoice -ge 1) -and ($modelChoice -le $modelOptions.Count)
        if (-not $isValid) { Write-Host "Opcao invalida. Tente novamente." -ForegroundColor Red }
    } while (-not $isValid)
    $selectedModel = $modelOptions[$modelChoice - 1]

    # Pergunta ao usuario o valor do beam size
    do {
        $beamSize = $null
        $beamSizeInput = Read-Host "Informe o valor do beam size (1 a 10)"
        $isValidBeam = [int]::TryParse($beamSizeInput, [ref]$beamSize) -and ($beamSize -ge 1) -and ($beamSize -le 10)
        if (-not $isValidBeam) { Write-Host "Beam size invalido. Tente novamente." -ForegroundColor Red }
    } while (-not $isValidBeam)

    # Pergunta ao usuario o valor da temperatura
    do {
        $temperature = $null
        $isValidTemp = [double]::TryParse((Read-Host "Informe o valor da temperatura (0 a 1, exemplo: 0,0 ou 0,5 ou 1,0) [use virgula como separador decimal]" -replace ",", "."), [ref]$temperature) -and ($temperature -ge 0) -and ($temperature -le 1)
        if (-not $isValidTemp) { Write-Host "Temperatura invalida. Use virgula como separador decimal (ex: 0,5)." -ForegroundColor Red }
    } while (-not $isValidTemp)
    
    # Pergunta se deseja processar inteiro ou por segmentos
    Write-Host "Deseja processar o arquivo inteiro ou por segmentos?"
    Write-Host "1 - Arquivo inteiro"
    Write-Host "2 - Por segmentos"
    do {
        $modoProcessamento = Read-Host "Escolha 1 ou 2"
        $isValidModo = $modoProcessamento -eq "1" -or $modoProcessamento -eq "2"
        if (-not $isValidModo) { Write-Host "Opcao invalida. Tente novamente." -ForegroundColor Red }
    } while (-not $isValidModo)

    # Pergunta ao usuario se deseja ativar o verbose
    Write-Host "Deseja ativar o modo verbose?"
    Write-Host "1 - Sim"
    Write-Host "2 - Nao"
    do {
        $verboseChoice = Read-Host "Escolha 1 para Sim ou 2 para Nao"
        $isValidVerbose = $verboseChoice -eq "1" -or $verboseChoice -eq "2"
        if (-not $isValidVerbose) { Write-Host "Opcao invalida. Tente novamente." -ForegroundColor Red }
    } while (-not $isValidVerbose)
    if ($verboseChoice -eq "1") {
        $verboseFlag = "--verbose True"
        $logFile = "F:\Whisper\log.txt"
        if (!(Test-Path $logFile)) {
            New-Item -ItemType File -Path $logFile -Force | Out-Null
        }
    } else {
        $verboseFlag = ""
        $logFile = $null
    }

    if ($modoProcessamento -eq "2") {
        # Processamento por segmentos
        $segmentTime = 0
        do {
            $segmentTime = Read-Host "Informe o tempo de cada segmento em segundos (ex: 300 para 5 minutos)"
            $isValidSeg = ($segmentTime -as [int]) -and ($segmentTime -gt 0)
            if (-not $isValidSeg) { Write-Host "Valor invalido. Tente novamente." -ForegroundColor Red }
        } while (-not $isValidSeg)

        foreach ($arquivo in $arquivos) {
            $segmentDir = Join-Path $outputSubDirectory ("segmentos_" + [IO.Path]::GetFileNameWithoutExtension($arquivo.Name))
            if (!(Test-Path $segmentDir)) { New-Item -ItemType Directory -Path $segmentDir | Out-Null }

            # Se nao ha progresso ou diretorio diferente, segmenta o arquivo
            if (-not $progresso -or $progresso.dir -ne $segmentDir) {
                Write-Host "Segmentando $($arquivo.Name)..."
                if ($tipoArquivo -eq "1") {
                    ffmpeg -i $arquivo.FullName -f segment -segment_time $segmentTime -c copy (Join-Path $segmentDir "segmento_%03d.mp4")
                } else {
                    ffmpeg -i $arquivo.FullName -f segment -segment_time $segmentTime -c copy (Join-Path $segmentDir "segmento_%03d.mp3")
                }
                Remove-ProgressoSegmentos
            }

            if ($tipoArquivo -eq "1") {
                $segmentos = Get-ChildItem -Path $segmentDir -Filter "segmento_*.mp4" | Sort-Object Name
            } else {
                $segmentos = Get-ChildItem -Path $segmentDir -Filter "segmento_*.mp3" | Sort-Object Name
            }
            $startIndex = 0
            if ($progresso -and $progresso.dir -eq $segmentDir) {
                $names = $segmentos | Select-Object -ExpandProperty Name
                $idx = $names.IndexOf($progresso.segmento)
                if ($idx -ge 0) { $startIndex = $idx + 1 }
            }

            for ($i = $startIndex; $i -lt $segmentos.Count; $i++) {
                $seg = $segmentos[$i]
                Write-Host "Processando segmento $($seg.Name)..." -ForegroundColor Yellow
                Save-ProgressoSegmentos $segmentDir $seg.Name
                $cmd = ("whisper `"$($seg.FullName)`" --model $selectedModel --language Portuguese --device cuda --temperature $temperature --beam_size $beamSize $verboseFlag --output_dir `"$outputSubDirectory`"" -replace '\s+', ' ')
                if ($logFile) {
                    Invoke-Expression "$cmd | Tee-Object -FilePath `"$logFile`" -Append"
                } else {
                    Invoke-Expression $cmd
                }
                Write-Host "Finalizado $($seg.Name)" -ForegroundColor Green
            }
            Remove-ProgressoSegmentos
        }
    } 
    else {
        # Processamento normal (arquivo inteiro)
        foreach ($arquivo in $arquivos) {
            Write-Host "Processando $($arquivo.Name)..." -ForegroundColor Yellow
            $cmd = ("whisper `"$($arquivo.FullName)`" --model $selectedModel --language Portuguese --device cuda --temperature $temperature --beam_size $beamSize $verboseFlag --output_dir `"$outputSubDirectory`"" -replace '\s+', ' ')
            if ($logFile) {
                Invoke-Expression "$cmd | Tee-Object -FilePath `"$logFile`" -Append"
            } else {
                Invoke-Expression $cmd
            }
            Write-Host "Modelo selecionado: $selectedModel" -ForegroundColor DarkGray
            Write-Host "Finalizado $($arquivo.Name)" -ForegroundColor Green
        }
    }

    Write-Host "Processamento em lote concluido!" -ForegroundColor Cyan
}
# Fim da funcao Start-VideosProcessing

# Checa ffmpeg antes de iniciar o processamento
Test-FFmpeg

do {
    Start-VideosProcessing
    Write-Host ""
    Write-Host "Pressione enter para fazer um novo processamento, ou qualquer tecla para sair" -ForegroundColor Cyan
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
} while ($key.VirtualKeyCode -eq 13)
