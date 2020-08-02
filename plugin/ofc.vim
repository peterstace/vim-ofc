autocmd TextChangedI * call OnTextChangedI()
autocmd InsertLeave * call Deactivate()
autocmd CursorMoved * call Deactivate()


set completeopt=noselect,preview,menuone

function OnTextChangedI()
	if &omnifunc == ''
		return
	endif

	if exists("s:state")
		if col('.') <= s:state.anchor
			call Deactivate()
			return
		endif
		if complete_info().selected != -1
			call Deactivate()
			return
		endif
		call TriggerUpdate()
	else
		call TriggerCompletion()
	endif
endfunction

let g:auto_complete_triggers = #{
	\ go: '\.$',
	\ }

function TriggerCompletion()
	let trigger = get(g:auto_complete_triggers, &filetype, '')
	if trigger == ''
		return
	endif

	let line = getline(line("."))[:col('.')-2]
	if line !~ trigger
		return
	endif

	" Find the start of the completion.
	let start = function(&omnifunc)(1, '')
	if start == -2 || start == -3
		" -2 and -3 indicate to cancel silently. See :help
		" complete-functions.
		return
	elseif start < 0
		" Negative other than -2 and -3 indicate the completions start at
		" the column of the cursor.
		let start = col('.') - 1
	endif

	let omnifunc_suggestions = function(&omnifunc)(0, '')
	if len(omnifunc_suggestions) == 0
		return
	endif
	let normalised_suggestions = NormaliseSuggestions(omnifunc_suggestions)

	let s:state = #{
		\ anchor: start,
		\ suggestions: normalised_suggestions,
	\ }

	call TriggerUpdate()
endfunction

function TriggerUpdate()
	let partial = getline(line("."))[s:state.anchor:col('.')-2]
	let items = Filter(partial, s:state.suggestions)
	if len(items) == 0
		call Deactivate()
		return
	endif
	call complete(s:state.anchor + 1, items)
endfunction

" NormaliseSuggestions accepts a suggestions result from invoking an omnifunc.
" It normalises and returns the result. The normalised form is a list of
" dicts.
function NormaliseSuggestions(suggestions)
	let suggestions = a:suggestions
	if type(suggestions) == v:t_dict
		let suggestions = suggestions.words
	endif
	if len(suggestions) == 0
		return suggestions
	endif
	let first = suggestions[0]
	if type(first) == v:t_string
		call map(suggestions, '#{word: v:val}')
	endif
	return suggestions
endfunction

function Filter(filter, suggestions)
	let words = map(copy(a:suggestions), 'v:val.word')
	let cmd = 'fzf --filter ' . shellescape(a:filter)
	let filtered_words = split(system(cmd, words), '\n')
	return filter(copy(a:suggestions), {idx, v -> index(filtered_words, v.word) != -1})
endfunction

function Deactivate()
	if exists("s:state")
		" TODO: close the popup window if it is open?
		echom "DEACTIVATE"
		unlet! s:state
	endif
endfunction
