vim9script

if exists('g:loaded_geminiask')
  finish
endif
g:loaded_geminiask = 1

command! -nargs=+ GeminiAsk geminiask#GeminiAsk(<q-args>)
command! -nargs=+ GeminiAskNew geminiask#GeminiAskNew(<q-args>)
command! -nargs=+ GeminiAskWithBuffer geminiask#GeminiAskWithBuffer(<q-args>)
command! -nargs=+ GeminiAskWithBufferNew geminiask#GeminiAskWithBufferNew(<q-args>)
command! GeminiClear geminiask#GeminiClear()