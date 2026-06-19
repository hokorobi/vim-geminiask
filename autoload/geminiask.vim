vim9script

# List to hold conversation history
var chat_history: list<dict<any>> = []

# Internal function to create a buffer only once after data is received
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

# Core transmission process (Streaming / Internal use)
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
        echoerr 'GeminiAsk: No response from Gemini.'
        return
      endif

      const model_content = { role: 'model', parts: [{ text: full_reply }] }
      add(chat_history, model_content)

      var last_line = line('$')
      append(last_line, ['', '---', ''])
      normal! G
      echo 'GeminiAsk: Response complete.'
    }
  })

  const ch = job_getchannel(job)
  if ch_status(ch) == 'open'
    ch_sendraw(ch, json_body)
    ch_close_in(ch)
  endif
enddef

# [Internal Shared Function 1] Validation, History Addition, and Transmission Start
def ExecuteAsk(prompt: string, display_prompt: string, msg: string)
  final api_key = get(g:, 'geminiask_apikey', '')
  if api_key == '' | echoerr 'GeminiAsk: g:geminiask_apikey is not set.' | return | endif
  if prompt == '' | echo 'GeminiAsk: Prompt is empty.' | return | endif

  echo msg

  const user_content = { role: 'user', parts: [{ text: prompt }] }
  add(chat_history, user_content)

  SendToGemini(display_prompt)
enddef

# [Internal Shared Function 2] Construct a prompt including current Vim buffer contents and send
def ExecuteAskWithBuffer(prompt: string, is_new: bool)
  if is_new
    export#GeminiClear()
  endif

  const buffer_lines = getline(1, '$')
  const filetype = &filetype

  var full_prompt = prompt .. "\n\n"
  full_prompt ..= "--- Target Buffer Contents ---\n"
  if filetype != ''
    full_prompt ..= $'```{filetype}' .. "\n"
  endif
  full_prompt ..= join(buffer_lines, "\n") .. "\n"
  if filetype != ''
    full_prompt ..= "```\n"
  endif

  var display_prompt = prompt .. " (Attaching current buffer contents"
  var msg = 'GeminiAsk: Querying Gemini with buffer contents...'
  if is_new
    display_prompt ..= ', new thread)'
    msg = 'GeminiAsk: Clearing history and querying Gemini with buffer contents...'
  else
    display_prompt ..= ')'
  endif

  ExecuteAsk(full_prompt, display_prompt, msg)
enddef

# --- Public interface functions (exposed to plugin/ side) ---

# Standard query function
export def GeminiAsk(prompt: string)
  ExecuteAsk(prompt, prompt, 'GeminiAsk: Querying Gemini...')
enddef

# Single-shot query function (New thread)
export def GeminiAskNew(prompt: string)
  export#GeminiClear()
  ExecuteAsk(prompt, prompt, 'GeminiAsk: Querying Gemini in a new thread...')
enddef

# Query function with current buffer contents attached
export def GeminiAskWithBuffer(prompt: string)
  ExecuteAskWithBuffer(prompt, false)
enddef

# Query function with current buffer contents attached to start a new conversation
export def GeminiAskWithBufferNew(prompt: string)
  ExecuteAskWithBuffer(prompt, true)
enddef

# Function to completely clear conversation history and delete the buffer itself
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
  echo 'GeminiAsk: Conversation history cleared and buffer deleted.'
enddef