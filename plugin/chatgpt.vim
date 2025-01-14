" ChatGPT Vim Plugin
"
" Ensure Python3 is available
if !has('python3')
  echo "Python 3 support is required for ChatGPT plugin"
  finish
endif

" Add ChatGPT dependencies
python3 << EOF
import sys
import vim
import os

try:
    import openai
except ImportError:
    print("Error: openai module not found. Please install with Pip and ensure equality of the versions given by :!python3 -V, and :python3 import sys; print(sys.version)")
    raise

def safe_vim_eval(expression):
    try:
        return vim.eval(expression)
    except vim.error:
        return None

openai.api_key = os.getenv('OPENAI_API_KEY') or safe_vim_eval('g:chat_gpt_key') or safe_vim_eval('g:openai_api_key')
openai.proxy = os.getenv("OPENAI_PROXY")
EOF

" Set default values for Vim variables if they don't exist
if !exists("g:chat_gpt_max_tokens")
  let g:chat_gpt_max_tokens = 2000
endif

if !exists("g:chat_gpt_temperature")
  let g:chat_gpt_temperature = 0.7
endif

if !exists("g:chat_gpt_model")
  let g:chat_gpt_model = 'gpt-3.5-turbo'
endif

if !exists("g:chat_gpt_lang")
  let g:chat_gpt_lang = ''
endif

if !exists("g:chat_gpt_split_direction")
  let g:chat_gpt_split_direction = 'horizontal'
endif

" Function to show ChatGPT responses in a new buffer
function! DisplayChatGPTResponse(response, finish_reason, chat_gpt_session_id)
  let response = a:response
  let finish_reason = a:finish_reason

  let chat_gpt_session_id = a:chat_gpt_session_id

  " if !bufexists(chat_gpt_session_id)
  "   if g:chat_gpt_split_direction ==# 'vertical'
  "     silent execute 'vnew '. chat_gpt_session_id
  "   else
  "     silent execute 'new '. chat_gpt_session_id
  "   endif
  "   call setbufvar(chat_gpt_session_id, '&buftype', 'nofile')
  "   call setbufvar(chat_gpt_session_id, '&bufhidden', 'hide')
  "   call setbufvar(chat_gpt_session_id, '&swapfile', 0)
  "   setlocal modifiable
  "   setlocal wrap
  "   call setbufvar(chat_gpt_session_id, '&ft', 'markdown')
  "   call setbufvar(chat_gpt_session_id, '&syntax', 'markdown')
  " endif
		" 
  " if bufwinnr(chat_gpt_session_id) == -1
  "   if g:chat_gpt_split_direction ==# 'vertical'
  "     execute 'vsplit ' . chat_gpt_session_id
  "   else
  "     execute 'split ' . chat_gpt_session_id
  "   endif
  " endif

  let last_lines = getbufline(chat_gpt_session_id, '$')
  let last_line = empty(last_lines) ? '' : last_lines[-1]

  let new_lines = substitute(last_line . response, '\n', '\r\n\r', 'g')
  let lines = split(new_lines, '\n')

  let clean_lines = []
  for line in lines
    call add(clean_lines, line)
    " call add(clean_lines, substitute(line, '\r', '', 'g'))
    " if empty(clean_lines)
    "   return
    " endif
    " execute "normal A" . clean_lines[0]

  endfor

  " call setbufline(chat_gpt_session_id, '$', clean_lines)
  " call cursor('$', 1)

  if empty(clean_lines)
    execute "normal A" . "\r"
    return
  endif
  execute "normal A" . clean_lines[0]

  if finish_reason != ''
    wincmd p
  endif
endfunction

" Function to interact with ChatGPT
function! ChatGPT(prompt, is_programmer) abort
  python3 << EOF

def chat_gpt(prompt, is_programmer):
  max_tokens = int(vim.eval('g:chat_gpt_max_tokens'))
  model = str(vim.eval('g:chat_gpt_model'))
  temperature = float(vim.eval('g:chat_gpt_temperature'))
  lang = str(vim.eval('g:chat_gpt_lang'))
  resp = lang and f" And respond in {lang}." or ""

  systemCtx = ''
  if is_programmer == True:
    systemCtx = {"role": "system", "content": f"You are a helpful expert programmer we are working together to solve complex coding challenges, and I need your help. Please make sure to wrap all code blocks in ``` annotate the programming language you are using. {resp}"}
  else:
    systemCtx = {"role": "system", "content": f""}
  messages = []
  session_id = 'gpt-persistent-session' if int(vim.eval('exists("g:chat_gpt_session_mode") && g:chat_gpt_session_mode')) else None


  # If session id exists and is in vim buffers
  if session_id:
    buffer = []

    for b in vim.buffers:
       # If the buffer name matches the session id
      if session_id in b.name:
        buffer = b[:]
        break

    # Read the lines from the buffer
    history = "\n".join(buffer).split('\n\n>>>')
    history.reverse()

    # Adding messages to history until token limit is reached
    token_count = max_tokens - len(prompt) - len(str(systemCtx))

    for line in history:
      if ':\n' in line:
        role, message = line.split(":\n")

        token_count -= len(message)

        if token_count > 0:
            messages.insert(0, {
                "role": role.lower(),
                "content": message
            })

  if session_id:
    # content = '\n\n>>>User:\n' + prompt + '\n\n>>>Assistant:\n'.replace("'", "''")
    content = ''

    vim.command("call DisplayChatGPTResponse('{0}', '', '{1}')".format(content.replace("'", "''"), session_id))
    vim.command("redraw")

  messages.append({"role": "user", "content": prompt})
  messages.insert(0, systemCtx)

  try:
    response = openai.ChatCompletion.create(
      model=model,
      messages=messages,
      max_tokens=max_tokens,
      stop='',
      temperature=temperature,
      stream=True
    )

    # Iterate through the response chunks
    for chunk in response:
      chunk_session_id = session_id if session_id else chunk["id"]
      choice = chunk["choices"][0]
      finish_reason = choice.get("finish_reason")
      content = choice.get("delta", {}).get("content")

      # Call DisplayChatGPTResponse with the finish_reason or content
      if finish_reason:
        vim.command("call DisplayChatGPTResponse('', '{0}', '{1}')".format(finish_reason.replace("'", "''"), chunk_session_id))
      elif content:
        vim.command("call DisplayChatGPTResponse('{0}', '', '{1}')".format(content.replace("'", "''"), chunk_session_id))

      vim.command("redraw")

  except Exception as e:
    print("Error:", str(e))

chat_gpt(vim.eval('a:prompt'), vim.eval('a:is_programmer'))
EOF
endfunction

" Function to send highlighted code to ChatGPT
function! SendHighlightedCodeToChatGPT(ask, context)
  let save_cursor = getcurpos()

  " Save the current yank register
  let save_reg = @@
  let save_regtype = getregtype('@')

  let [line_start, col_start] = getpos("'<")[1:2]
  let [line_end, col_end] = getpos("'>")[1:2]

  " Yank the visually selected text into the unnamed register
  execute 'normal! ' . line_start . 'G' . col_start . '|v' . line_end . 'G' . col_end . '|y'

  " Send the yanked text to ChatGPT
  let yanked_text = ''

  if (col_end - col_start > 0) || (line_end - line_start > 0)
    let yanked_text = '```' . "\n" . @@ . "\n" . '```'
  endif

  let prompt = a:context . ' ' . "\n" . yanked_text

  if a:ask == 'rewrite'
    let prompt = 'I have the following code snippet, can you rewrite it more idiomatically?' . "\n" . yanked_text . "\n"
    if len(a:context) > 0
      let prompt = 'I have the following code snippet, can you rewrite to' . a:context . '?' . "\n" . yanked_text . "\n"
    endif
  elseif a:ask == 'review'
    let prompt = 'I have the following code snippet, can you provide a code review for?' . "\n" . yanked_text . "\n"
  elseif a:ask == 'document'
    let syntax = &syntax
    let prompt = 'Given the following code snippet written in ' . syntax . ' return documentation following language pattern conventions' . "\n" . yanked_text . "\n"
  elseif a:ask == 'explain'
    let prompt = 'I have the following code snippet, can you explain it?' . "\n" . yanked_text
    if len(a:context) > 0
      let prompt = 'I have the following code snippet, can you explain, ' . a:context . '?' . "\n" . yanked_text
    endif
  elseif a:ask == 'test'
    let prompt = 'I have the following code snippet, can you write a test for it?' . "\n" . yanked_text
    if len(a:context) > 0
      let prompt = 'I have the following code snippet, can you write a test for it, ' . a:context . '?' . "\n" . yanked_text
    endif
  elseif a:ask == 'fix'
    let prompt = 'I have the following code snippet, it has an error I need you to fix:' . "\n" . yanked_text . "\n"
    if len(a:context) > 0
      let prompt = 'I have the following code snippet I would want you to fix, ' . a:context . ':' . "\n" . yanked_text . "\n"
    endif
  endif

  call ChatGPT(prompt, v:true)

  " Restore the original yank register
  let @@ = save_reg
  call setreg('@', save_reg, save_regtype)
  let curpos = getcurpos()
  call setpos("'<", curpos)
  call setpos("'>", curpos)
  call setpos('.', save_cursor)

endfunction
"
" Function to generate a commit message
function! GenerateCommitMessage()
  " Save the current position and yank register
  let save_cursor = getcurpos()
  let save_reg = @@
  let save_regtype = getregtype('@')

  " Yank the entire buffer into the unnamed register
  normal! ggVGy

  " Send the yanked text to ChatGPT
  let yanked_text = @@
  let prompt = 'I have the following code changes, can you write a helpful commit message, including a short title?' . "\n" .  yanked_text

  call ChatGPT(prompt, v:true)
endfunction

" Function to generate a commit message
function! GenerateCompletiton(ask)
  let select_text = s:get_visual_text()
  let prompt = len(select_text) == 0 ? a:ask : select_text . a:ask 
  call ChatGPT(prompt, v:false)
endfunction

" Function to generate a commit message
function! GenerateEdit(ask)
  let select_text = s:get_visual_text()

	" delete visual selected
  let start = getpos("'<")
  let end = getpos("'>")
  execute start[1] . "," . end[1] . "d"

  let prompt = len(select_text) == 0 ? a:ask : select_text . a:ask 
  call ChatGPT(prompt, v:false)
endfunction

function! s:get_visual_text()
  try
    let pos = getpos('')
    normal `<
    let start_line = line('.')
    let start_col = col('.')
    normal `>
    let end_line = line('.')
    let end_col = col('.')
    call setpos('.', pos)

    let tmp = @@
    silent normal gvy
    let selected = @@
    let @@ = tmp
    return selected
  catch
    return ''
  endtry
endfunction


" Menu for ChatGPT
function! s:ChatGPTMenuSink(id, choice)
  call popup_hide(a:id)
  let choices = {1:'Ask', 2:'rewrite', 3:'explain', 4:'test', 5:'review', 6:'document'}
  if a:choice > 0 && a:choice < 6
    call SendHighlightedCodeToChatGPT(choices[a:choice], input('Prompt > '))
  endif
endfunction

function! s:ChatGPTMenuFilter(id, key)
  if a:key == '1' || a:key == '2' || a:key == '3' || a:key == '4' || a:key == '5'
    call s:ChatGPTMenuSink(a:id, a:key)
  else " No shortcut, pass to generic filter
    return popup_filter_menu(a:id, a:key)
  endif
endfunction

function! ChatGPTMenu() range
  echo a:firstline. a:lastline
  call popup_menu([ '1. Ask', '2. Rewrite', '3. Explain', '4. Test', '5. Review', '6. Document'], #{
        \ pos: 'topleft',
        \ line: 'cursor',
        \ col: 'cursor+2',
        \ title: ' Chat GPT ',
        \ highlight: 'question',
        \ borderchars: ['─', '│', '─', '│', '╭', '╮', '╯', '╰'],
        \ callback: function('s:ChatGPTMenuSink'),
        \ border: [],
        \ cursorline: 1,
        \ padding: [0,1,0,1],
        \ filter: function('s:ChatGPTMenuFilter'),
        \ mapping: 0,
        \ })
endfunction

" Expose mappings
" vnoremap <silent> <Plug>(chatgpt-menu) :call ChatGPTMenu()<CR>

" Commands to interact with ChatGPT
command! -range -nargs=? Ask call SendHighlightedCodeToChatGPT('Ask',<q-args>)
command! -range -nargs=? Explain call SendHighlightedCodeToChatGPT('explain', <q-args>)
command! -range Review call SendHighlightedCodeToChatGPT('review', '')
command! -range -nargs=? Document call SendHighlightedCodeToChatGPT('document', <q-args>)
command! -range -nargs=? Rewrite call SendHighlightedCodeToChatGPT('rewrite', <q-args>)
command! -range -nargs=? UnitTest call SendHighlightedCodeToChatGPT('test',<q-args>)
command! -range -nargs=? Fix call SendHighlightedCodeToChatGPT('fix', <q-args>)
command! GenerateCommit call GenerateCommitMessage()
command! -range -nargs=? Completeion call GenerateCompletiton(<q-args>)
command! -range -nargs=? Edit call GenerateEdit(<q-args>)
