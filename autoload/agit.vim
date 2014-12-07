let s:save_cpo = &cpo
set cpo&vim

let s:V = vital#of('agit')
let s:P = s:V.import('Prelude')
let s:String = s:V.import('Data.String')
let s:List = s:V.import('Data.List')
let s:Process = s:V.import('Process')
let s:OptionParser = s:V.import('OptionParser')

let s:agit_vital = {
\ 'V' : s:V,
\ 'P' : s:P,
\ 'String' : s:String,
\ 'List' : s:List,
\ 'Process' : s:Process,
\ 'OptionParser' : s:OptionParser,
\ }

let s:agit_preset_views = {
\ 'default': [
\   {'name': 'log'},
\   {'name': 'stat',
\    'layout': 'botright vnew'},
\   {'name': 'diff',
\    'layout': 'belowright {winheight(".") * 3 / 4}new'}
\ ],
\ 'file': [
\   {'name': 'filelog'},
\   {'name': 'catfile',
\    'layout': 'botright vnew'},
\ ]}
let s:fugitive_enabled = get(g:, 'loaded_fugitive', 0)

let s:parser = s:OptionParser.new()
call s:parser.on('--dir=VALUE', 'Launch Agit on the specified directory instead of the buffer direcotry.',
\ {'completion' : 'file', 'default': ''})
call s:parser.on('--file=VALUE', 'Specify file name traced by Agit file. (Available on Agit file)',
\ {'completion' : 'file', 'default': '%'})

function! agit#complete_command(arglead, cmdline, cursorpos)
  return s:parser.complete_greedily(a:arglead, a:cmdline, a:cursorpos)
endfunction

function! agit#vital()
  return s:agit_vital
endfunction

function! agit#launch(args)
  try
    let parsed_args = s:parse_args(a:args)
    if has_key(parsed_args, 'help')
      call s:parser.help()
      return
    endif
    let git_dir = s:get_git_dir(parsed_args.dir)
    let git = agit#git#new(git_dir)
    let git.path = expand(parsed_args.file)
    if !filereadable(git.path)
        throw "Agit: File not found: " . git.path
    endif
    let git.abspath = fnamemodify(git.path, ':p')
    let git.relpath = git.normalizepath(git.abspath)
    let git.views = parsed_args.preset
    call agit#bufwin#agit_tabnew(git)
    let t:git = git
  catch /Agit: /
    echohl ErrorMsg | echomsg v:exception | echohl None
  endtry
endfunction

function! s:parse_args(args)
  try
    let parse_result = s:parser.parse(a:args)
    if empty(parse_result.__unknown_args__)
      let parse_result.preset = s:agit_preset_views.default
    elseif has_key(s:agit_preset_views, parse_result.__unknown_args__[0])
      let parse_result.preset = s:agit_preset_views[parse_result.__unknown_args__[0]]
    else
      throw 'vital: OptionParser: Unknown option was specified: ' . parse_result.__unknown_args__[0]
    endif
    return parse_result
  catch /vital: OptionParser: /
    let msg = matchstr(v:exception, 'vital: OptionParser: \zs.*')
    throw 'Agit: ' . msg
  endtry
endfunction

function! agit#print_commitmsg()
  let hash = agit#extract_hash(getline('.'))
  if hash != ''
    echo t:git.commitmsg(hash)
  else
    echo
  endif
endfunction

function! agit#remote_scroll(win_type, direction)
  if a:win_type ==# 'stat'
    call agit#bufwin#move_to('stat')
  elseif a:win_type ==# 'diff'
    call agit#bufwin#move_to('diff')
  endif
  if a:direction ==# 'down'
    execute "normal! \<C-d>"
  elseif a:direction ==# 'up'
    execute "normal! \<C-u>"
  endif
  call agit#bufwin#move_to('log')
endfunction

function! agit#yank_hash()
  call setreg(v:register, agit#extract_hash(getline('.')))
  echo 'yanked ' . getreg(v:register)
endfunction

function! agit#exit()
  if !exists('t:git')
    return
  endif
  silent! tabclose!
endfunction

function! agit#show_commit()
  if has_key(w:, 'view') && has_key(w:view, 'emmit')
    call w:view.emmit()
  endif
endfunction

function! agit#reload() abort
  if !exists('t:git')
    return
  endif
  let pos_save = getpos('.')
  try
    call t:git.fire_init()
  finally
    call setpos('.', pos_save)
  endtry
endfunction

function! s:get_git_dir(basedir)
  if empty(a:basedir)
    " if fugitive exists
    if s:fugitive_enabled && exists('b:git_dir')
      return b:git_dir
    else
      let current_path = expand('%:p:h')
    endif
  else
    let current_path = a:basedir
  endif
  let cdcmd = haslocaldir() ? 'lcd ' : 'cd '
  let cwd = getcwd()
  execute cdcmd . current_path
  if s:Process.has_vimproc() && s:P.is_windows()
    let toplevel_path = vimproc#system('git --no-pager rev-parse --show-toplevel')
    let has_error = vimproc#get_last_status() != 0
  else
    let toplevel_path = system('git --no-pager rev-parse --show-toplevel')
    let has_error = v:shell_error != 0
  endif
  execute cdcmd . cwd
  if has_error
    throw 'Agit: Not a git repository.'
  endif
  return s:String.chomp(toplevel_path) . '/.git'
endfunction

function! agit#extract_hash(str)
  return matchstr(a:str, '\[\zs\x\{7\}\ze\]$')
endfunction

function! agit#agitgit(arg, confirm, bang)
  let arg = substitute(a:arg, '\c<hash>', agit#extract_hash(getline('.')), 'g')
  if match(arg, '\c<branch>') >= 0
    let cword = expand('<cword>')
    silent let branch = agit#git#exec('rev-parse --symbolic ' . cword, t:git.git_dir)
    let branch = substitute(branch, '\n\+$', '', '')
    if agit#git#get_last_status() != 0
      echomsg 'Not a branch name: ' . cword
      return
    endif
    let arg = substitute(arg, '\c<branch>', branch, 'g')
  endif
  let curpos = stridx(arg, '\%#')
  if curpos >= 0
    let arg = substitute(arg, '\\%#', '', 'g')
    call feedkeys(':AgitGit ' . arg . "\<C-r>=setcmdpos(" . (curpos + 9) . ")?'':''\<CR>", 'n')
    " This function will be recursively called without \%#.
  else
    if a:confirm
      echon "'git " . s:String.chomp(arg) . "' ? [y/N]"
      let yn = nr2char(getchar())
      if yn !=? 'y'
        return
      endif
    endif
    echo agit#git#exec(arg, t:git.git_dir, a:bang)
    call agit#reload()
  endif
endfunction

function! agit#agitgit_confirm(arg)
endfunction

function! agit#agit_git_compl(arglead, cmdline, cursorpos)
  if a:cmdline =~# '^AgitGit\s\+\w*$'
    return join(split('add bisect branch checkout push pull rebase reset fetch commit cherry-pick remote merge reflog show stash', ' '), "\n")
  else
    return agit#revision_list()
  endif
endfunction

function! agit#revision_list()
  return agit#git#exec('rev-parse --symbolic --branches --remotes --tags', t:git.git_dir)
  \ . join(['HEAD', 'ORIG_HEAD', 'MERGE_HEAD', 'FETCH_HEAD'], "\n")
endfunction

function! s:git_checkout(branch_name)
  echo agit#git#exec('checkout ' . a:branch_name, t:git.git_dir)
  call agit#reload()
endfunction

function! s:git_checkout_b()
  let branch_name = input('git checkout -b ')
  echo ''
  echo agit#git#exec('checkout -b ' . branch_name, t:git.git_dir)
  call agit#reload()
endfunction

function! s:git_branch_d(branch_name)
  echon "Are you sure you want to delete branch '" . a:branch_name . "' [y/N]"
  if nr2char(getchar()) ==# 'y'
    echo agit#git#exec('branch -D ' . a:branch_name, t:git.git_dir)
    call agit#reload()
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
