# vim-geminiask

A Vim9script plugin for asynchronous, streaming conversation directly within Vim using the Google Gemini API.

It supports asynchronous processing (`job`) and Server-Sent Events (`SSE`) streaming, allowing generated responses to be written to a buffer in real time without locking up Vim. It also features a smart behavior that delays opening the buffer window until the first piece of data arrives.

## Features

- **Streaming Support**: Responses from the AI are written to the buffer in real time.
- **Fully Asynchronous**: Does not block Vim operations while the response is being generated.
- **Smart Window**: Avoids opening unnecessary windows until the initial response is actually received.
- **Context Preservation**: Unless specified by a command, it maintains previous conversation history (context) for an ongoing chat experience.
- **Markdown Output**: Responses are automatically output to a scratch buffer with `filetype=markdown`.

## Configuration

Before using the plugin, you must configure your Gemini API key in your `~/.vimrc` (or `_vimrc`).

```vim
" Set your Gemini API access key (Required)
let g:geminiask_apikey = 'AIzaSy...'

" Set the Gemini model name to use (Optional, Default: 'gemini-2.5-flash')
let g:geminiask_model = 'gemini-2.5-pro'

```

## Commands

| Command | Description |
| --- | --- |
| `:GeminiAsk {prompt}` | Sends `{prompt}` to Gemini while maintaining the current conversation thread (history). |
| `:GeminiAskNew {prompt}` | Completely clears previous conversation history and the existing output buffer, then sends `{prompt}` to Gemini in a new thread. |
| `:GeminiAskWithBuffer {prompt}` | Maintains the current conversation thread (history) and sends `{prompt}` along with the entire content of the currently active buffer attached as a code block. Useful for refactoring requests or asking questions about existing code. |
| `:GeminiAskWithBufferNew {prompt}` | Completely clears previous conversation history and the existing output buffer, then sends `{prompt}` to Gemini along with the content of the current buffer. |
| `:GeminiClear` | Initializes (resets) the conversation history (context) and forcibly deletes (`bwipeout`) the open `GeminiAsk` buffer and window. |

## Buffer Specifications

The AI's responses are output to a special scratch buffer (`nofile`) named `GeminiAsk` in Markdown format (`filetype=markdown`).
When the transmission completes, a divider line (`---`) is automatically inserted, making it ready to accept the next question.
