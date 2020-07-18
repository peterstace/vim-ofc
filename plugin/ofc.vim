autocmd TextChangedI * call OnTextChangedI()
autocmd InsertLeave * call Deactivate()
autocmd CursorMoved * call Deactivate()

function OnTextChangedI()
	if &omnifunc == ''
		return
	endif

	let current_char = getline(line('.'))[col('.')-2]

	if !exists("s:state")
		if current_char != '.'
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
			let start = col('.')
		endif

		let omnifunc_suggestions = function(&omnifunc)(0, '')
		if len(omnifunc_suggestions) == 0
			return
		endif
		let normalised_suggestions = NormaliseSuggestions(omnifunc_suggestions)

		let s:state = #{
			\ anchor: col('.') - 1,
			\ suggestions: normalised_suggestions,
			\ filtered_suggestions: normalised_suggestions,
			\ partial: '',
			\ pup_id: 0,
			\ index: -1,
		\ }

		let popup_entries = BuildPopupEntries(s:state.suggestions)
		let s:state.pup_id = popup_create(popup_entries, #{pos: 'topleft', line: 'cursor+1', col: 'cursor-1'})

		return
	endif

	if col('.') <= s:state.anchor
		call Deactivate()
		return
	endif

	if current_char == "\t"
		let Restore = SaveRegister('"')
	
		" Delete the typed out filter. If the user hasn't type _any_ filter,
		" then we can't delete it (since 'd0h' would be interpreted to delete
		" to the start of the line and then moving left rather than deleting 0
		" to the left).
		let delete_amount = col('.') - s:state.anchor - 2
		if delete_amount
			execute 'normal! d' . delete_amount . 'h'
		else
			" delete the tab that the user just put in
			execute 'normal! x'
		endif

		" Cycle through to the next filtered suggestion. If we go past then
		" end, then we want to select none (indicated by -1), which
		" corresponds to the user's typed filter.
		let s:state.index += 1
		if s:state.index == len(s:state.filtered_suggestions)
			let s:state.index = -1
		endif

		" Insert the selection (either from the filtered suggestions list, or
		" form the user's typed partial filter).
		if s:state.index == -1
			let @" = s:state.partial
		else
			let @" = s:state.filtered_suggestions[s:state.index].word
		endif
		execute 'normal! ""p'
		call feedkeys("\<Right>")

		call Restore()
	else
		let s:state.partial = getline(line('.'))[s:state.anchor:col('.')]
		let s:state.filtered_suggestions = Filter(s:state.partial, s:state.suggestions)
		if len(s:state.filtered_suggestions) == 0
			call Deactivate()
			return
		endif
	endif

	let popup_entries = BuildPopupEntries(s:state.filtered_suggestions)
	call popup_settext(s:state.pup_id, popup_entries)
endfunction

function Filter(filter, suggestions)
	let words = map(copy(a:suggestions), 'v:val.word')
	let cmd = 'fzf -f ' . shellescape(a:filter)
	let filtered_words = split(system(cmd, words), '\n')
	return filter(copy(a:suggestions), {idx, v -> index(filtered_words, v.word) != -1})
endfunction

function Deactivate()
	if exists("s:state")
		call popup_close(s:state.pup_id)
	endif
	unlet! s:state
endfunction

function BuildPopupEntries(suggestions)
	let max_word = max(map(copy(a:suggestions), {_, x -> len(get(x, 'word', ''))}))
	let max_kind = max(map(copy(a:suggestions), {_, x -> len(get(x, 'kind', ''))}))
	let max_menu = max(map(copy(a:suggestions), {_, x -> len(get(x, 'menu', ''))}))
	let texts =  map(copy(a:suggestions), {_, x -> printf(
		\ " %-*s %*s %-*s",
		\ max_word, get(x, "word", ""),
		\ max_kind, get(x, "kind", ""),
		\ max_menu, get(x, "menu", ""))})
	let entries = []
	let idx = 0
	for txt in texts
		let entry = #{text: txt}
		if idx == s:state.index
			if !exists("g:ofc_highlight_defined")
				call prop_type_add("ofc_highlight", #{highlight: "PmenuSel"})
				let g:ofc_highlight_defined = 1
			endif
			let length = max_word + max_kind + max_menu + 3
			let entry.props = [#{col:1, length: length, type: "ofc_highlight"}]
		endif
		call add(entries, entry)
		let idx += 1
	endfor
	return entries
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

" SaveRegister saves the register and returns a closure that will restore it.
func SaveRegister(reg)
	let content = getreg(a:reg)
	let reg_type = getregtype(a:reg)
	return {-> setreg(a:reg, content, reg_type)}
endfunction
