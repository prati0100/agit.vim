if exists("b:current_syntax")
  finish
endif

syn case ignore
syn sync minlines=150

syn include @agitDiffInc syntax/diff.vim

syn region agitHeader start=/\%^/ end=/^$/ contains=agitHeaderLabel
syn match agitHeaderLabel /^\w\+:/ contained display
syn match agitHeaderLabel /^commit/ contained display

syn region agitDiff start=/^diff --git/ end=/^\%(^diff --git\)\@=\|\%$/ contains=@agitDiffInc

hi def link agitHeaderLabel Label

let b:current_syntax = "agit_diff"
