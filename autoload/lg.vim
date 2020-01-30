fu lg#catch_error() abort "{{{1
    if get(g:, 'my_verbose_errors', 0)
        let func_name = matchstr(v:throwpoint, 'function \zs.\{-}\ze,')
        let line = matchstr(v:throwpoint, '\%(function \)\?.\{-}, \zsline \d\+')

        echohl ErrorMsg
        if !empty(func_name)
            echom 'Error detected while processing function '..func_name..':'
        else
            " the error comes from a (temporary?) file
            echom 'Error detected while processing '..matchstr(v:throwpoint, '.\{-}\ze,')..':'
        endif
        echohl LineNr
        echom line..':'
    endif

    echohl ErrorMsg
    " Even if you set “my_verbose_errors”, when this function will be called
    " from a function implementing an operator  (g@), only the last message will
    " be visible (i.e. v:exception).
    " But  it  doesn't matter. All  the  messages  have  been written  in  Vim's
    " log. So, `:WTF` will be able to show us where the error comes from.
    echom v:exception
    echohl NONE

    " It's important  to return  an empty string. Because  often, the  output of
    " this function will be executed or inserted. Check `vim-interactive-lists`,
    " and `vim-readline`.
    return ''
endfu

fu lg#vim_parent() abort "{{{1
    "    ┌────────────────────────────┬─────────────────────────────────────┐
    "    │ :echo getpid()             │ print the PID of Vim                │
    "    ├────────────────────────────┼─────────────────────────────────────┤
    "    │ $ ps -p <Vim PID> -o ppid= │ print the PID of the parent of Vim  │
    "    ├────────────────────────────┼─────────────────────────────────────┤
    "    │ $ ps -p $(..^..) -o comm=  │ print the name of the parent of Vim │
    "    └────────────────────────────┴─────────────────────────────────────┘
    return expand('`ps -p $(ps -p '..getpid()..' -o ppid=) -o comm=`')
endfu

fu lg#set_stl(stl, ...) abort "{{{1
    " TODO: Once 8.1.1372 has been ported to Nvim, delete this function, and perform these refactorings:{{{
    "
    "     call lg#set_stl('foo')
    "     →
    "     setl stl=foo
    "
    " ---
    "
    "     call lg#set_stl('foo', 'bar')
    "     →
    "     let &l:stl = '%!g:statusline_winid == win_getid() ? "foo" : "bar"'
    "
    " Or if `foo`/`bar` is too complex:
    "
    "     call lg#set_stl('foo', 'bar')
    "     →
    "     setl stl=%!plugin#stl()
    "     fu plugin#stl()
    "         return g:statusline_winid == win_getid() ? 'foo' : 'bar'
    "     endfu
    "
    " ---
    "
    " Also, make sure to include `set stl<` inside `b:undo_ftplugin` (except for dirvish).
    "}}}
    if !has('nvim')
        if a:0
            let &l:stl = '%!'..s:snr..'set_stl('..string(a:stl)..', '..string(a:1)..')'
        else
            let &l:stl = a:stl
        endif
        let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe')..'| set stl<'
        return
    endif

    let &l:stl = a:stl

    exe 'augroup '..&ft..'_set_stl'
        au! * <buffer>
        if a:0
            " Why `BufWinEnter`?{{{
            "
            " The current function is called when `FileType` is fired.
            " It  installs the  next autocmd  which will  set `'stl'`  later, to
            " overwrite the value set by `vim-statusline`.
            " It works  as long as  `WinEnter` is fired right  after `FileType`,
            " which is often the case, but not always:
            "
            "     $ nvim +'helpg foobar' +cclose
            "     :copen
            "
            " In this example, when we re-open  the qf window, `WinEnter` is not
            " fired right after `FileType`; but `BufWinEnter` is.
            "}}}
            exe 'au WinEnter,BufWinEnter <buffer> let &l:stl = '..string(a:stl)
            exe 'au WinLeave <buffer> let &l:stl = '..string(a:1)
        else
            exe 'au BufWinEnter,WinEnter,WinLeave <buffer> let &l:stl = '..string(a:stl)
        endif
    augroup END

    " Why don't you include `set stl<` for dirvish?{{{
    "
    " Because the dirvish plugin does sth weird.
    " It fires two `FileType` events.
    " After the  first one, `BufWinEnter`  is fired,  but after the  second one,
    " neither `BufWinEnter` nor `WinEnter` is fired.
    "
    " So, when  the second  `FileType` is  fired, if  `b:undo_ftplugin` includes
    " `set stl<`, the local value of `'stl'` will be made empty, and it won't be
    " reset. IOW, initially, the  status line will just contain the  path to the
    " viewed directory.
    "}}}
    let b:undo_ftplugin = get(b:, 'undo_ftplugin', 'exe')
        \ ..(&ft isnot# 'dirvish' ? '| set stl<' : '')
        \ ..'| exe "au! '..&ft..'_set_stl * <buffer>"'
endfu

fu s:snr() abort
    return matchstr(expand('<sfile>'), '.*\zs<SNR>\d\+_')
endfu
let s:snr = get(s:, 'snr', s:snr())

fu s:set_stl(stl_focused, stl_unfocused) abort
    return a:stl_{g:statusline_winid == win_getid() ? '' : 'un'}focused
endfu

fu lg#termname() abort "{{{1
    if exists('$TMUX')
        return system('tmux display -p "#{client_termname}"')[:-2]
    else
        return $TERM
    endif
endfu

fu lg#win_execute(id, cmd, ...) abort "{{{1
    " TODO: Is this a bug?{{{
    "
    "     $ vim -Nu NONE -o /tmp/file{1..2} +'set wmh=0|call win_execute(win_getid(2), "wincmd _")'
    "
    " The current window is squashed to 0 lines, so the cursor is not visible anymore.
    " Note that  if you want  to maximize an  unfocused window (e.g.  the second
    " one), you can/should simply execute `:2resize`.
    "}}}
    let silent = a:0 ? [a:1] : []
    " `a:cmd` could contain a call to a script-local function.{{{
    "
    " When that happens, `s:` will be replaced by `<SNR>123_` where `123` is the
    " script id of the current file.
    " This is wrong; it should be  the id of the script where `lg#win_execute()`
    " was invoked; we need to resolve `s:` manually.
    "}}}
    " FIXME: For the translation to work, `lg#win_execute()` must be called by a script-local function.{{{
    "
    " Not  necessarily directly,  but a  script-local function  must be  present
    " somewhere in the stack of function calls.
    "}}}
    let snr = matchstr(expand('<sfile>'), '\m\C.*\zs<SNR>\d\+_')
    let cmd = substitute(a:cmd, '\m\C\<s:\ze\h\+(', snr, 'g')
    if !has('nvim')
        call call('win_execute', [a:id, cmd] + silent)
    else
        " Make sure that the window layout is correct after running these commands:{{{
        "
        "     $ nvim +'helpg foobar'
        "
        " The height of the qf window should be 10.
        "
        " ---
        "
        "     $ nvim +'helpg foobar' +'wincmd t | sp'
        "
        " The top window should be squashed.
        "}}}

        " preserve current window
        let curwinid = win_getid()
        " preserve previous window
        let prevwinid = win_getid(winnr('#'))
        " preserve window size of target window
        let [tarheight, tarwidth, winrestcmd] = [winheight(a:id), winwidth(a:id), winrestcmd()]
        " Why `:noa`?{{{
        "
        " From `:h win_execute()`:
        "
        " > The  window will  temporarily be  made the  current window,  without
        " > triggering autocommands.
        "}}}
        noa call win_gotoid(a:id)
        let before = winrestcmd()
        " Why not `:noa`?{{{
        "
        " > When executing  {command} autocommands  will be triggered,  this may
        " > have unexpected side effects.  Use |:noautocmd| if needed.
        "}}}
        exe cmd
        let after = winrestcmd()
        " Rationale:{{{
        "
        " If `cmd` makes the layout change,  it means that the current layout is
        " desired, and  that's the  one we  should restore at  the end;  not the
        " original layout.
        "}}}
        if after isnot# before | let winrestcmd = after | endif
        noa call win_gotoid(prevwinid)
        noa call win_gotoid(curwinid)
        " TODO: Should we remove the condition, and restore the layout unconditionally?
        " Rationale:{{{
        "
        " Suppose you have set `'wmh'` to 0.
        " As a result, the  other windows can be squashed to 0  lines, but only when
        " they are not focused.
        "
        " When focusing a window, its height will always be set to at least one line.
        " See `:h 'wmh`:
        "
        " > They will return to at least one line when they become active
        " > (since the cursor has to have somewhere to go.)
        "
        " IOW, the mere  fact of temporarily focusing a window  – even while the
        " autocmds are disabled – may increase its height by 1.
        "}}}
        noa exe winrestcmd
        if (&winminheight == 0 && tarheight != winheight(a:id))
        \ || (&winminwidth == 0 && tarwidth != winwidth(a:id))
            noa exe winrestcmd
        endif
    endif
endfu

fu lg#win_getid(arg) abort "{{{1
    if a:arg is# 'P'
        let winnr = index(map(range(1, winnr('$')), {_,v -> getwinvar(v, '&pvw')}), 1) + 1
        if winnr == 0 | return 0 | endif
        return win_getid(winnr)
    elseif a:arg is# '#'
        let winnr = winnr('#')
        return win_getid(winnr)
    endif
endfu

