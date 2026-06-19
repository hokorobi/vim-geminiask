vim9script

# 会話履歴を保持するリスト
var chat_history: list<dict<any>> = []

# データ受信後に一度だけ呼ばれるバッファ作成関数（内部用）
def PrepareBufferAfterResponse(prompt: string): number
  const buf_nr = bufnr('^GeminiAsk$')
  var win_id = -1

  if buf_nr != -1
    win_id = bufwinid(buf_nr)
    if win_id != -1
      win_gotoid(win_id)
    else
      execute $'buffer {buf_nr}'
    endif
    setlocal modifiable
  else
    vnew
    silent! file GeminiAsk
    setlocal buftype=nofile bufhidden=wipe noswapfile filetype=markdown
  endif

  var last_line = line('$')
  if last_line == 1 && getline(1) == ''
    last_line = 0
  endif

  var lines = [$'## User: {prompt}', '', '## Gemini: ']
  append(last_line, lines)
  normal! G
  return line('$')
enddef

# コアとなる送信処理（ストリーミング・内部用）
def SendToGemini(prompt: string)
  final api_key = get(g:, 'geminiask_apikey', '')
  final model = get(g:, 'geminiask_model', 'gemini-2.5-flash')
  const url = $'https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse&key={api_key}'
  const json_body = json_encode({ contents: chat_history })
  const cmd = ['curl', '-s', '-N', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', '@-', url]

  var append_line = 0
  var full_reply = ''
  var is_first_chunk = true

  const job = job_start(cmd, {
    in_io: 'pipe',
    out_io: 'pipe',
    err_io: 'null',
    out_cb: (channel, msg) => {
      if msg !~ '^data:\s*'
        return
      endif
      const json_str = substitute(msg, '^data:\s*', '', '')

      var response = {}
      try
        response = json_decode(json_str)
      catch
        return
      endtry

      if response->has_key('candidates')
          && !empty(response.candidates)
          && response.candidates[0]->has_key('content')
          && !empty(response.candidates[0].content.parts)

        const text_chunk = response.candidates[0].content.parts[0].text
        full_reply ..= text_chunk

        if is_first_chunk
          append_line = PrepareBufferAfterResponse(prompt)
          is_first_chunk = false
        endif

        const current_line_text = getline(append_line)
        const new_lines = split(current_line_text .. text_chunk, "\n", 1)

        setline(append_line, new_lines[0])
        if len(new_lines) > 1
          append(append_line, new_lines[1 :])
          append_line += len(new_lines) - 1
        endif

        normal! G
        redraw
      endif
    },
    close_cb: (channel) => {
      if full_reply == ''
        echoerr 'GeminiAsk: Geminiから応答がありませんでした。'
        return
      endif

      const model_content = { role: 'model', parts: [{ text: full_reply }] }
      add(chat_history, model_content)

      var last_line = line('$')
      append(last_line, ['', '---', ''])
      normal! G
      echo 'GeminiAsk: 回答が完了しました。'
    }
  })

  const ch = job_getchannel(job)
  if ch_status(ch) == 'open'
    ch_sendraw(ch, json_body)
    ch_close_in(ch)
  endif
enddef

# 【共通内部関数①】バリデーション・履歴追加・送信開始
def ExecuteAsk(prompt: string, display_prompt: string, msg: string)
  final api_key = get(g:, 'geminiask_apikey', '')
  if api_key == '' | echoerr 'GeminiAsk: g:geminiask_apikey が設定されていません。' | return | endif
  if prompt == '' | echo 'GeminiAsk: 質問が空です。' | return | endif

  echo msg

  const user_content = { role: 'user', parts: [{ text: prompt }] }
  add(chat_history, user_content)

  SendToGemini(display_prompt)
enddef

# 【共通内部関数②】現在のVimバッファの内容を含んだプロンプトを構築して送信
def ExecuteAskWithBuffer(prompt: string, is_new: bool)
  if is_new
    export#GeminiClear()
  endif

  const buffer_lines = getline(1, '$')
  const filetype = &filetype

  var full_prompt = prompt .. "\n\n"
  full_prompt ..= "--- 対象のバッファ内容 ---\n"
  if filetype != ''
    full_prompt ..= $'```{filetype}' .. "\n"
  endif
  full_prompt ..= join(buffer_lines, "\n") .. "\n"
  if filetype != ''
    full_prompt ..= "```\n"
  endif

  var display_prompt = prompt .. " (現在のバッファ内容を添付"
  var msg = 'GeminiAsk: バッファ内容を含めて Geminiに問い合わせ中...'
  if is_new
    display_prompt ..= '・新規スレッド)'
    msg = 'GeminiAsk: 履歴をクリアし、バッファ内容を含めて Geminiに問い合わせ中...'
  else
    display_prompt ..= ')'
  endif

  ExecuteAsk(full_prompt, display_prompt, msg)
enddef

# --- 以下、外部（plugin/側）に公開するインターフェース関数 ---

# 通常の質問関数
export def GeminiAsk(prompt: string)
  ExecuteAsk(prompt, prompt, 'GeminiAsk: Geminiに問い合わせ中...')
enddef

# 単発の質問関数
export def GeminiAskNew(prompt: string)
  export#GeminiClear()
  ExecuteAsk(prompt, prompt, 'GeminiAsk: 新しいスレッドで Geminiに問い合わせ中...')
enddef

# 現在のバッファ内容を添付して質問する関数
export def GeminiAskWithBuffer(prompt: string)
  ExecuteAskWithBuffer(prompt, false)
enddef

# 現在のバッファ内容を添付し、新しく会話を始める関数
export def GeminiAskWithBufferNew(prompt: string)
  ExecuteAskWithBuffer(prompt, true)
enddef

# 会話履歴とバッファ自体を完全に削除する関数
export def GeminiClear()
  if chat_history == []
    return
  endif

  chat_history = []
  const buf_nr = bufnr('^GeminiAsk$')
  if buf_nr != -1
    const win_id = bufwinid(buf_nr)
    if win_id != -1
      win_execute(win_id, 'quit')
    endif
    if bufexists(buf_nr)
      execute $'bwipeout! {buf_nr}'
    endif
  endif
  echo 'GeminiAsk: 会話履歴をクリアし、バッファを削除しました。'
enddef