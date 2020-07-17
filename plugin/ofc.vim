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

		let s:state = {}

		" Find the start of the completion.
		let start = function(&omnifunc)(1, '')

		if start == -2 || start == -3
			" -2 and -3 indicate to cancel silently. See :help
			" complete-functions. We have to deactivate, since
			" s:state has already been defined.
			call Deactivate()
			return
		elseif start < 0
			" Negative other than -2 and -3 indicate the completions start at
			" the column of the cursor.
			let start = col('.')
		endif
		
		let s:state.anchor = col('.') - 1

		let s:state.suggestions = NormaliseSuggestions(function(&omnifunc)(0, ''))

		if len(s:state.suggestions) == 0
			call Deactivate()
			return
		endif

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

		if !exists("s:state.index")
			let s:state.index = 0
		else
			let s:state.index += 1
			if s:state.index == len(s:state.filtered_suggestions)
				unlet s:state.index
			endif
		endif

		if exists("s:state.index")
			let @" = s:state.filtered_suggestions[s:state.index].word
		else
			let @" = s:state.partial
		endif
		execute 'normal! ""p'
		call feedkeys("\<Right>")

		call Restore()

		let popup_entries = BuildPopupEntries(s:state.filtered_suggestions)
		call popup_settext(s:state.pup_id, popup_entries)

		return
	endif

	let s:state.partial = getline(line('.'))[s:state.anchor:col('.')]

	let s:state.filtered_suggestions = Filter(s:state.partial, s:state.suggestions)
	if len(s:state.filtered_suggestions) == 0
		call Deactivate()
		return
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
	if exists("s:state.pup_id")
		call popup_close(s:state.pup_id)
	endif
	unlet! s:state
endfunction

call prop_type_add("highlight", #{highlight: "Error"})

function BuildPopupEntries(suggestions)
	let max_word = max(map(copy(a:suggestions), {_, x -> get(x, 'word', '')}))
	let max_kind = max(map(copy(a:suggestions), {_, x -> get(x, 'kind', '')}))
	let texts =  map(copy(a:suggestions), {_, x -> printf(
		\ " %-*s %*s %s",
		\ max_word, get(x, "word", ""),
		\ max_kind, get(x, "kind", ""),
		\ get(x, "menu", ""))})
	let max_text = max(map(copy(texts), {_, x -> len(x)}))
	let entries = []
	let idx = 0
	for txt in texts
		let entry = #{text: txt}
		if exists("s:state.index") && idx == s:state.index
			let entry.props = [#{col:1, length: max_text, type: "highlight"}]
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
