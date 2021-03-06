Red/System [
	Title:   "Red execution stack functions"
	Author:  "Nenad Rakocevic"
	File: 	 %stack.reds
	Tabs:	 4
	Rights:  "Copyright (C) 2011-2012 Nenad Rakocevic. All rights reserved."
	License: {
		Distributed under the Boost Software License, Version 1.0.
		See https://github.com/dockimbel/Red/blob/master/BSL-License.txt
	}
]

stack: context [										;-- call stack
	verbose: 0
	
	dyn-info!: alias struct! [
		header [integer!]
		code   [integer!]
		count  [integer!]
		locals [integer!]
	]
	
	call-frame!: alias struct! [
		header [integer!]								;-- symbol ID of the calling function
		prev   [red-value!]								;-- previous frame base
		ctx	   [node!]									;-- context for function's name
	]
	
	arg-stk:		as red-block!	0					;-- argument stack (should never be relocated)
	call-stk:		as red-block!	0					;-- call stack (should never be relocated)
	args-series:	as series!		0
	calls-series:	as series!		0
	a-end: 			as red-value!	0
	c-end: 			as call-frame!	0
	arguments:		as red-value!	0
	bottom:  		as red-value!	0
	top:	 		as red-value!	0
	cbottom: 		as call-frame!	0
	ctop:	 		as call-frame! 	0
	
	acc-mode?: 		no									;-- YES: accumulate expressions on stack
	body-symbol:	0									;-- symbol ID
	anon-symbol:	0									;-- symbol ID
	
	#define MARK_STACK(type) [
		func [
			fun [red-word!]
		][
			#if debug? = yes [if verbose > 0 [print-line "stack/mark"]]

			if ctop = c-end [
				print-line ["^/*** Error: call stack overflow!^/"]
				throw RED_ERROR
			]
			ctop/header: type or (fun/symbol << 8)
			ctop/prev:	 arguments
			ctop/ctx:	 fun/ctx
			ctop: ctop + 1
			arguments: top								;-- top of stack becomes frame base

			#if debug? = yes [if verbose > 1 [dump]]
		]
	]
	
	#define STACK_SET_FRAME [
		either ctop = cbottom [
			arguments: bottom
			top: bottom
		][
			top: arguments + 1							;-- keep last value on stack
			arguments: ctop/prev
		]
	]
	
	;-- header flags
	#enum flags! [
		FLAG_FUNCTION:	80000000h						;-- function! call
		FLAG_NATIVE:	40000000h						;-- native! or action! call
		FLAG_ROUTINE:	20000000h						;--	<reserved>
		FLAG_TRY:		10000000h						;--	TRY native
		FLAG_CATCH:		08000000h						;-- CATCH native
		FLAG_THROW_ATR:	04000000h						;-- Throw function attribut
		FLAG_CATCH_ATR:	02000000h						;--	Catch function attribut
		FLAG_EVAL:		01000000h						;-- Interpreter root frame
		FLAG_DYN_CALL:	11000000h						;-- Dynamic call (alternative stack mode)
	]
	
	init: does [
		arg-stk:  block/make-in root 1024
		call-stk: block/make-in root 512

		set-flag arg-stk/node  flag-series-fixed or flag-series-nogc
		set-flag call-stk/node flag-series-fixed or flag-series-nogc

		;-- Shortcuts for stack buffers simpler and faster access
		;-- (stack buffers are not resizable with such approach
		;-- this can be made more flexible (but slower) if necessary
		;-- in the future)

		args-series:  GET_BUFFER(arg-stk)
		calls-series: GET_BUFFER(call-stk)

		a-end: as cell!		  (as byte-ptr! args-series)  + args-series/size
		c-end: as call-frame! (as byte-ptr! calls-series) + calls-series/size

		arguments:	args-series/tail					;@@ incorrect?!
		bottom:  	args-series/offset
		top:	 	args-series/tail					;@@ incorrect?!
		cbottom: 	as call-frame! calls-series/offset
		ctop:	 	as call-frame! calls-series/tail	;@@ incorrect?!
		
		body-symbol: words/_body/symbol
		anon-symbol: words/_anon/symbol
	]
	
	check-call: does [
		if acc-mode? [check-dyn-call]
	]

	reset: func [
		return:  [cell!]
		/local
			s	 [series!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/reset"]]
		
		either acc-mode? [check-dyn-call][top: arguments]
		arguments
	]
	
	keep: func [
		return:  [cell!]
		/local
			s	 [series!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/keep"]]
		
		top: arguments + 1								;-- keep last value in arguments slot
		if acc-mode? [check-dyn-call]
		arguments
	]
	
	mark-native: MARK_STACK(FLAG_NATIVE)
	mark-func:	 MARK_STACK(FLAG_FUNCTION)
	mark-try:	 MARK_STACK(FLAG_TRY)
	mark-catch:	 MARK_STACK(FLAG_CATCH)
	mark-eval:	 MARK_STACK(FLAG_EVAL)
	mark-dyn:	 MARK_STACK(FLAG_DYN_CALL)
	
	get-call: func [
		return: [red-word!]
		/local
			p	[call-frame!]
			sym [integer!]
	][
		p: ctop
		until [
			p: p - 1
			sym: p/header >> 8 and FFFFh
			any [
				all [sym <> body-symbol	sym <> anon-symbol]
				p < cbottom
			]
		]
		word/at p/ctx sym
	]
	
	revert: does [
		#if debug? = yes [if verbose > 0 [print-line "stack/revert"]]

		assert cbottom < ctop
		ctop: ctop - 1
		either ctop = cbottom [
			arguments: bottom
			top: bottom
		][
			top: arguments
			arguments: ctop/prev
		]
		
		#if debug? = yes [if verbose > 1 [dump]]
	]
	
	unwind-part: does [
		#if debug? = yes [if verbose > 0 [print-line "stack/unwind-part"]]

		assert cbottom < ctop
		ctop: ctop - 1
		either ctop = cbottom [
			arguments: bottom
		][
			arguments: ctop/prev
		]
		top: top - 1

		#if debug? = yes [if verbose > 1 [dump]]
	]
		
	unwind: does [
		#if debug? = yes [if verbose > 0 [print-line "stack/unwind"]]

		assert cbottom < ctop
		ctop: ctop - 1
		STACK_SET_FRAME
		if acc-mode? [check-dyn-call]
		
		#if debug? = yes [if verbose > 1 [dump]]
	]
	
	unwind-last: func [
		return:  [red-value!]
		/local
			last [red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/unwind-last"]]

		last: arguments
		unwind
		copy-cell last arguments
	]
	
	unroll-frames: func [flags [integer!]][
		assert cbottom < ctop
		until [
			ctop: ctop - 1
			any [
				ctop <= cbottom
				flags and ctop/header = flags
			]
		]
		STACK_SET_FRAME
		ctop: ctop + 1									;-- ctop points past the current call frame
	]

	unroll: func [
		flags	 [integer!]
		/local
			last [red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/unroll"]]

		last: arguments
		unroll-frames flags
		copy-cell last ctop/prev
	]
	
	adjust: does [
		top: top - 1
		copy-cell top top - 1
		check-call
	]
	
	trace: func [
		int		[red-integer!]
		buffer	[red-string!]
		part	[integer!]
		return: [integer!]
		/local
			top	  [call-frame!]
			base  [call-frame!]
			sym	  [integer!]
	][
		top: as call-frame! int/value
		value: ALLOC_TAIL(root)
		int: as red-integer! value
		int/header: TYPE_INTEGER
		base: cbottom
		
		until [
			sym: base/header >> 8 and FFFFh
			
			if all [sym <> body-symbol sym <> anon-symbol][
				if base > cbottom [
					string/concatenate-literal buffer " "
					part: part - 4
				]
				part: word/form 
					word/make-at sym value
					buffer
					null
					part
			]
			base: base + 1
			base >= top									;-- defensive test
		]
		part
	]
	
	set-stack: func [
		err [red-object!]
		/local
			base [red-value!]
			int	 [red-integer!]
	][
		base: object/get-values err
		int: as red-integer! base + error/get-stack-id
		int/header: TYPE_INTEGER
		int/value:  as-integer ctop
	]
	
	throw-error: func [
		err [red-object!]
		/local
			extra [red-value!]
			saved [red-value!]
	][
		error/set-where err as red-value! get-call
		set-stack err
		
		extra: top
		unroll-frames FLAG_TRY

		ctop: ctop - 1
		assert ctop >= cbottom
		top: extra

		if all [
			ctop = cbottom 
			FLAG_TRY and ctop/header <> FLAG_TRY
		][
			saved: arguments
			arguments: extra							;-- use the top stack frame @@ overflows!
			set-last as red-value! err
			natives/print*
			arguments: saved
		]
		stack/push as red-value! err
		throw RED_ERROR
	]
	
	eval?: func [
		return: [logic!]
		/local
			cframe [call-frame!]
	][
		cframe: ctop
		until [
			cframe: cframe - 1
			if FLAG_EVAL and cframe/header = FLAG_EVAL [return yes]
			cframe <= cbottom
		]
		no
	]
	
	set-last: func [
		last	[red-value!]
		return: [red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/set-last"]]
		
		copy-cell last arguments
	]
	
	push*: func [
		return:  [red-value!]
		/local
			cell [red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/push*"]]

		cell: top
		top: top + 1
		if top >= a-end [
			print-line ["^/*** Error: arguments stack overflow!^/"]
			throw RED_ERROR
		]
		cell
	]
	
	push: func [
		value 	  [red-value!]
		return:   [red-value!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/push"]]
		
		copy-cell value top
		push*
	]
	
	pop: func [
		positions [integer!]
	][
		#if debug? = yes [if verbose > 0 [print-line "stack/pop"]]
		
		top: top - positions
	]
	
	top-type?: func [
		return:  [integer!]
		/local
			value [red-value!]
	][
		value: top - 1
		TYPE_OF(value)
	]
	
	func?: func [
		return: [logic!]
		/local
			value [red-value!]
			type  [integer!]
	][
		value: top - 1
		type: TYPE_OF(value)
		any [											;@@ replace with ANY_FUNCTION?
			type = TYPE_FUNCTION
			type = TYPE_ROUTINE
		]
	]
	
	defer-call: func [
		name   [red-word!]
		code   [integer!]
		count  [integer!]
		octx [node!]
		/local
			info [dyn-info!]
	][
		;mark-native words/_anon
		integer/push as-integer octx					;-- store optional wrapping object pointer
		
		info: as dyn-info! push*
		info/header: TYPE_POINT
		info/code:   code								;-- store wrapping function pointer
		info/count:  count								;-- store caller's arity
		info/locals: -2									;-- store caller's locals count
		
		mark-dyn name									;-- open new frame
		acc-mode?: yes
		arguments/header: TYPE_VALUE					;-- use TYPE_VALUE to signal "no argument"
	]
	
	push-call: func [
		path [red-path!]
		idx  [integer!]
		code [integer!]
		octx [node!]
		/local
			fun		 [red-function!]
			p		 [red-path!]
			info	 [dyn-info!]
			counters [integer!]
	][
		;mark-native words/_anon
		fun: as red-function! top - 1
		
		assert any [
			TYPE_OF(fun) = TYPE_FUNCTION
			TYPE_OF(fun) = TYPE_ROUTINE
		]
		counters: _function/calc-arity path fun idx
		p: as red-path! copy-cell as red-value! path push*
		p/head: idx										;-- store path with function's index
		
		integer/push as-integer octx					;-- store optional wrapping object pointer
		
		info: as dyn-info! push*
		info/header: TYPE_POINT
		info/code:   code								;-- store wrapping function pointer
		info/count:  counters and FFFFh					;-- store caller's arity
		info/locals: counters >> 16						;-- store caller's locals count
		
		mark-dyn as red-word! block/rs-abs-at as red-block! path idx  ;-- open new frame
		acc-mode?: yes
		
		either zero? (counters and FFFFh) [
			arguments/header: TYPE_UNSET
			check-dyn-call								;-- short path to call with no arguments
		][
			arguments/header: TYPE_VALUE				;-- use TYPE_VALUE to signal "no argument"
		]
	]
	
	check-dyn-call: func [
		/local
			int		   [red-integer!]
			fun		   [red-function!]
			obj		   [red-object!]
			base	   [red-value!]
			last	   [red-value!]
			info	   [dyn-info!]
			ctx		   [node!]
			octx	   [node!]
			more	   [series!]
			p		   [call-frame!]
			dyn?	   [logic!]
			new-frame? [logic!]
			code
	][
		p: ctop - 1
		if p < cbottom [exit]
		
		if all [
			FLAG_DYN_CALL and p/header = FLAG_DYN_CALL
			TYPE_OF(arguments) <> TYPE_VALUE
		][
			info: as dyn-info! arguments - 1
			unless zero? info/count [info/count: info/count - 1]
			
			if zero? info/count [
				base: arguments
				either info/locals = -2 [
					fun: null
					new-frame?: no
				][
					ctx: null
					fun: as red-function! base - 4
					more: as series! fun/more/value
					int: as red-integer! more/offset + 4
					obj: as red-object! base - 5
					case [
						TYPE_OF(obj) = TYPE_OBJECT  [ctx: obj/ctx]
						TYPE_OF(int) = TYPE_INTEGER [ctx: as node! int/value]
						true						[ctx: null]
					]

					new-frame?: info/locals = -1
					case [
						info/locals > 0 [_function/init-locals info/locals]
						new-frame?		[_function/lay-frame]
						true			[0]					;-- 0 locals case, do nothing
					]
				]
				
				code: as function! [octx [node!]] info/code
				int: as red-integer! base - 2
				octx: as node! int/value
				
				acc-mode?: no							;-- temporary disable accumulative mode
				unless null? fun [_function/call fun ctx] ;-- run the detected function
				unless zero? info/code [code octx]		;-- run wrapper code (stored as function)
				if new-frame? [unwind-last]				;-- close new frame created for handling refinements
				
				last: arguments
				unwind									;-- close frame opened in 'push-call
				either all [
					null? fun							;-- for defered calls only
					arguments + 3 < top					;-- check if not first argument of parent call?
				][
					copy-cell last arguments + 1
					top: top - 2						;-- adjust stack to right position for next argument
				][
					copy-cell last arguments			;-- unwind-last
				]
				
				;base: arguments
				;unwind
				;push base
				acc-mode?: yes
				
				p: ctop - 1								;-- decide to keep or not the accumulative mode on
				either p < cbottom [
					acc-mode?: no						;-- bottom of stack reached, switch back to normal
				][
					dyn?: FLAG_DYN_CALL and p/header = FLAG_DYN_CALL
					either dyn? [check-dyn-call][acc-mode?: no] ;-- if another dyn call pending, keep the mode on
				]
			]
		]
	]

	#if debug? = yes [
		dump: does [									;-- debug purpose only
			print-line "^/---- Argument stack ----"
			dump-memory
				as byte-ptr! bottom
				4
				(as-integer top + 1 - bottom) >> 4
			print-line ["arguments: " arguments]
			print-line ["top: " top]
			
			print-line "^/---- Call stack ----"
			dump-memory
				as byte-ptr! cbottom
				4
				(as-integer ctop + 2 - cbottom) >> 4
			print-line ["ctop: " ctop]
		]
	]
]
