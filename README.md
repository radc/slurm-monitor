# Slurm Monitor TUI

![Bash](https://img.shields.io/badge/Bash-Script-121011?logo=gnu-bash)
![Slurm](https://img.shields.io/badge/Slurm-HPC-blue)
![Platform](https://img.shields.io/badge/Platform-Linux-informational)
![Status](https://img.shields.io/badge/Status-Active-success)
![License](https://img.shields.io/badge/License-MIT-green)

An interactive Bash-based monitor for Slurm jobs, logs, and job details.

## Language

- [English](#english)
- [Português](#portugues)
- [繁體中文（台灣）](#zh-tw)

---

## English

### Overview

**Slurm Monitor TUI** is a lightweight interactive terminal monitor for **Slurm jobs**, **stdout/stderr logs**, and **job details**, written entirely in **Bash**.

It was created as a more practical alternative to a simple `watch` command, with a workflow that feels closer to a minimal `htop`-style interface.

### Features

- Interactive terminal UI in Bash
- Monitors jobs with `squeue`
- Shows job details with `scontrol`
- Uses `sacct` as fallback when available
- Tries to resolve `StdOut`, `StdErr`, `StdIn`, and `WorkDir`
- Refreshes logs faster than Slurm metadata
- Supports manual log selection when paths are unresolved
- Can browse a log directory and filter files by selected job ID
- Colorized job states
- Keyboard shortcuts for navigation

### Refresh policy

Default behavior:

- **Logs:** every **2 seconds**
- **Slurm data:** every **30 seconds**

This keeps log monitoring responsive while avoiding unnecessary load on Slurm.

### Requirements

- `bash`
- `squeue`
- `scontrol`
- `sacct` (recommended)
- `tail`
- `find`
- `awk`
- `sed`
- `tput`

### Usage

```bash
chmod +x slurm-monitor.sh
./slurm-monitor.sh /path/to/logs
```

With fallback log files:

```bash
./slurm-monitor.sh /path/to/logs /path/to/default.out /path/to/default.err
```

Using environment variables:

```bash
LOG_DIR=/path/to/logs \
LOG_REFRESH=2 \
SLURM_REFRESH=30 \
QUEUE_VISIBLE_ROWS=4 \
./slurm-monitor.sh
```

### Main shortcuts

- `Up / Down` or `k / j`: select job
- `Enter`: open details
- `Tab`: cycle views
- `1`: stdout + stderr
- `2`: stdout only
- `3`: stderr only
- `4`: details
- `l`: open log picker
- `p`: pause or resume
- `r`: redraw
- `R`: force Slurm refresh
- `+ / -`: adjust log refresh interval
- `g / G`: first or last job
- `q`: quit

### Log picker shortcuts

- `Up / Down` or `k / j`: move in file list
- `o`: assign selected file to stdout
- `e`: assign selected file to stderr
- `a`: auto-assign logs
- `c`: clear manual assignments
- `Enter`, `Esc`, or `l`: close picker

### Developed with ChatGPT

This script was developed with the assistance of **ChatGPT**.

### Suggestions welcome

Suggestions for improvements are very welcome.  
Feel free to open an issue or submit a pull request.

---

## Portugues

### Visão geral

**Slurm Monitor TUI** é um monitor interativo de terminal para **jobs do Slurm**, **logs de stdout/stderr** e **detalhes de jobs**, escrito inteiramente em **Bash**.

Ele foi criado como uma alternativa mais prática a um simples comando com `watch`, com uma experiência mais próxima de uma interface mínima no estilo `htop`.

### Funcionalidades

- Interface interativa de terminal em Bash
- Monitora jobs com `squeue`
- Mostra detalhes do job com `scontrol`
- Usa `sacct` como fallback quando disponível
- Tenta resolver `StdOut`, `StdErr`, `StdIn` e `WorkDir`
- Atualiza os logs mais rápido do que os metadados do Slurm
- Permite seleção manual de logs quando os caminhos não são resolvidos
- Pode navegar em um diretório de logs e filtrar arquivos pelo job ID selecionado
- Estados dos jobs com cores
- Atalhos de teclado para navegação

### Política de atualização

Comportamento padrão:

- **Logs:** a cada **2 segundos**
- **Dados do Slurm:** a cada **30 segundos**

Isso mantém o monitoramento dos logs responsivo sem gerar carga desnecessária no Slurm.

### Requisitos

- `bash`
- `squeue`
- `scontrol`
- `sacct` (recomendado)
- `tail`
- `find`
- `awk`
- `sed`
- `tput`

### Uso

```bash
chmod +x slurm-monitor.sh
./slurm-monitor.sh /path/to/logs
```

Com arquivos de log de fallback:

```bash
./slurm-monitor.sh /path/to/logs /path/to/default.out /path/to/default.err
```

Usando variáveis de ambiente:

```bash
LOG_DIR=/path/to/logs \
LOG_REFRESH=2 \
SLURM_REFRESH=30 \
QUEUE_VISIBLE_ROWS=4 \
./slurm-monitor.sh
```

### Principais atalhos

- `Up / Down` ou `k / j`: selecionar job
- `Enter`: abrir detalhes
- `Tab`: alternar visualizações
- `1`: stdout + stderr
- `2`: apenas stdout
- `3`: apenas stderr
- `4`: detalhes
- `l`: abrir seletor de logs
- `p`: pausar ou retomar
- `r`: redesenhar
- `R`: forçar atualização do Slurm
- `+ / -`: ajustar intervalo de atualização dos logs
- `g / G`: primeiro ou último job
- `q`: sair

### Atalhos do seletor de logs

- `Up / Down` ou `k / j`: mover na lista de arquivos
- `o`: atribuir o arquivo selecionado ao stdout
- `e`: atribuir o arquivo selecionado ao stderr
- `a`: tentar atribuição automática
- `c`: limpar atribuições manuais
- `Enter`, `Esc` ou `l`: fechar o seletor

### Desenvolvido com ChatGPT

Este script foi desenvolvido com o auxílio do **ChatGPT**.

### Sugestões são bem-vindas

Sugestões de melhoria são muito bem-vindas.  
Sinta-se à vontade para abrir uma issue ou enviar um pull request.

---

## Zh-TW

### 簡介

**Slurm Monitor TUI** 是一個以 **Bash** 撰寫的互動式終端監控工具，用來監看 **Slurm jobs**、**stdout/stderr logs** 與 **job 詳細資訊**。

它是為了提供比單純 `watch` 指令更方便的使用體驗，整體風格接近輕量版的 `htop`。

### 功能

- 以 Bash 撰寫的互動式終端介面
- 使用 `squeue` 監看 jobs
- 使用 `scontrol` 顯示 job 詳細資訊
- 可在需要時以 `sacct` 作為備援
- 嘗試解析 `StdOut`、`StdErr`、`StdIn` 與 `WorkDir`
- logs 更新頻率高於 Slurm 中繼資料
- 當路徑無法解析時可手動指定 log
- 可瀏覽 log 目錄，並依目前選取的 job ID 過濾檔案
- job 狀態使用顏色顯示
- 提供鍵盤快捷鍵操作

### 更新策略

預設行為：

- **Logs：**每 **2 秒**
- **Slurm 資料：**每 **30 秒**

這樣可以保持 log 監看即時，同時避免對 Slurm 造成不必要的負擔。

### 需求

- `bash`
- `squeue`
- `scontrol`
- `sacct`（建議）
- `tail`
- `find`
- `awk`
- `sed`
- `tput`

### 使用方式

```bash
chmod +x slurm-monitor.sh
./slurm-monitor.sh /path/to/logs
```

搭配備援 log 路徑：

```bash
./slurm-monitor.sh /path/to/logs /path/to/default.out /path/to/default.err
```

使用環境變數：

```bash
LOG_DIR=/path/to/logs \
LOG_REFRESH=2 \
SLURM_REFRESH=30 \
QUEUE_VISIBLE_ROWS=4 \
./slurm-monitor.sh
```

### 主要快捷鍵

- `Up / Down` 或 `k / j`：選擇 job
- `Enter`：開啟詳細資訊
- `Tab`：切換顯示模式
- `1`：stdout + stderr
- `2`：只看 stdout
- `3`：只看 stderr
- `4`：詳細資訊
- `l`：開啟 log picker
- `p`：暫停或恢復
- `r`：重新繪製
- `R`：強制刷新 Slurm
- `+ / -`：調整 log 更新間隔
- `g / G`：跳到第一個或最後一個 job
- `q`：離開

### Log picker 快捷鍵

- `Up / Down` 或 `k / j`：在檔案列表中移動
- `o`：將選取檔案指定為 stdout
- `e`：將選取檔案指定為 stderr
- `a`：自動配對 logs
- `c`：清除手動指定
- `Enter`、`Esc` 或 `l`：關閉 picker

### 使用 ChatGPT 協助開發

此腳本是在 **ChatGPT** 的協助下開發完成的。

### 歡迎提供建議

非常歡迎提供改進建議。  
歡迎提出 issue 或送出 pull request。