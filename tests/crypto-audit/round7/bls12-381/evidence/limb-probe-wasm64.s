	.file	"bls7_limb_probe.dca375cd9ad65df9-cgu.0"
	.functype	__multi3 (i64, i64, i64, i64, i64) -> ()
	.globaltype	__stack_pointer, i64
	.functype	adc_new (i64, i64, i64, i64) -> (i64)
	.functype	adc_old (i64, i64, i64, i64) -> (i64)
	.functype	mac_comba (i64, i64, i64, i64, i64) -> (i64)
	.functype	mac_new (i64, i64, i64, i64, i64) -> (i64)
	.functype	mac_old (i64, i64, i64, i64, i64) -> (i64)
	.functype	sbb_new (i64, i64, i64, i64) -> (i64)
	.functype	sbb_old (i64, i64, i64, i64) -> (i64)
	.functype	sqr_new (i64, i64, i64, i64) -> (i64)
	.functype	sqr_old (i64, i64, i64, i64) -> (i64)
	.section	.text.adc_new,"",@
	.globl	adc_new
	.type	adc_new,@function
adc_new:
	.functype	adc_new (i64, i64, i64, i64) -> (i64)
	local.get	3
	local.get	1
	local.get	0
	i64.add 
	local.tee	0
	local.get	2
	i64.add 
	local.tee	2
	i64.store	0
	local.get	2
	local.get	0
	i64.lt_u
	i64.extend_i32_u
	local.get	0
	local.get	1
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.section	.text.adc_old,"",@
	.globl	adc_old
	.type	adc_old,@function
adc_old:
	.functype	adc_old (i64, i64, i64, i64) -> (i64)
	local.get	3
	local.get	1
	local.get	0
	i64.add 
	local.tee	0
	local.get	2
	i64.add 
	local.tee	2
	i64.store	0
	local.get	0
	local.get	1
	i64.lt_u
	i64.extend_i32_u
	local.get	2
	local.get	0
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.section	.text.mac_comba,"",@
	.globl	mac_comba
	.type	mac_comba,@function
mac_comba:
	.functype	mac_comba (i64, i64, i64, i64, i64) -> (i64)
	.local  	i64, i64
	local.get	4
	local.get	3
	i64.const	32
	i64.shr_u
	local.get	2
	i64.const	32
	i64.shr_u
	local.tee	5
	local.get	1
	i64.const	4294967295
	i64.and 
	local.tee	6
	i64.mul 
	i64.add 
	local.get	2
	i64.const	4294967295
	i64.and 
	local.tee	2
	local.get	1
	i64.const	32
	i64.shr_u
	local.tee	1
	i64.mul 
	local.get	0
	i64.const	32
	i64.shr_u
	i64.add 
	local.get	2
	local.get	6
	i64.mul 
	local.get	0
	i64.const	4294967295
	i64.and 
	i64.add 
	local.get	3
	i64.const	4294967295
	i64.and 
	i64.add 
	local.tee	2
	i64.const	32
	i64.shr_u
	i64.add 
	local.tee	0
	i64.const	4294967295
	i64.and 
	i64.add 
	local.tee	3
	i64.const	32
	i64.shl 
	local.get	2
	i64.const	4294967295
	i64.and 
	i64.or  
	i64.store	0
	local.get	0
	i64.const	32
	i64.shr_u
	local.get	5
	local.get	1
	i64.mul 
	i64.add 
	local.get	3
	i64.const	32
	i64.shr_u
	i64.add 
	end_function

	.section	.text.mac_new,"",@
	.globl	mac_new
	.type	mac_new,@function
mac_new:
	.functype	mac_new (i64, i64, i64, i64, i64) -> (i64)
	.local  	i64
	global.get	__stack_pointer
	i64.const	16
	i64.sub 
	local.tee	5
	global.set	__stack_pointer
	local.get	5
	local.get	2
	i64.const	0
	local.get	1
	i64.const	0
	call	__multi3
	local.get	4
	local.get	2
	local.get	1
	i64.mul 
	local.tee	2
	local.get	0
	i64.add 
	local.tee	1
	local.get	3
	i64.add 
	local.tee	0
	i64.store	0
	local.get	5
	i64.load	8
	local.set	3
	local.get	5
	i64.const	16
	i64.add 
	global.set	__stack_pointer
	local.get	3
	local.get	1
	local.get	2
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	local.get	0
	local.get	1
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.section	.text.mac_old,"",@
	.globl	mac_old
	.type	mac_old,@function
mac_old:
	.functype	mac_old (i64, i64, i64, i64, i64) -> (i64)
	.local  	i64, i64, i64, i64
	local.get	4
	local.get	2
	i64.const	4294967295
	i64.and 
	local.tee	5
	local.get	1
	i64.const	4294967295
	i64.and 
	local.tee	6
	i64.mul 
	local.tee	7
	i64.const	32
	i64.shr_u
	local.get	5
	local.get	1
	i64.const	32
	i64.shr_u
	local.tee	8
	i64.mul 
	i64.add 
	local.tee	5
	i64.const	4294967295
	i64.and 
	local.get	2
	i64.const	32
	i64.shr_u
	local.tee	2
	local.get	6
	i64.mul 
	i64.add 
	local.tee	6
	i64.const	32
	i64.shl 
	local.get	7
	i64.const	4294967295
	i64.and 
	i64.or  
	local.tee	7
	local.get	0
	i64.add 
	local.tee	1
	local.get	3
	i64.add 
	local.tee	0
	i64.store	0
	local.get	5
	i64.const	32
	i64.shr_u
	local.get	2
	local.get	8
	i64.mul 
	i64.add 
	local.get	6
	i64.const	32
	i64.shr_u
	i64.add 
	local.get	1
	local.get	7
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	local.get	0
	local.get	1
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.section	.text.sbb_new,"",@
	.globl	sbb_new
	.type	sbb_new,@function
sbb_new:
	.functype	sbb_new (i64, i64, i64, i64) -> (i64)
	.local  	i64
	local.get	3
	local.get	0
	local.get	1
	i64.sub 
	local.tee	4
	local.get	2
	i64.const	63
	i64.shr_u
	local.tee	2
	i64.sub 
	i64.store	0
	i64.const	0
	local.get	0
	local.get	1
	i64.lt_u
	local.get	4
	local.get	2
	i64.lt_u
	i32.or  
	i64.extend_i32_u
	i64.sub 
	end_function

	.section	.text.sbb_old,"",@
	.globl	sbb_old
	.type	sbb_old,@function
sbb_old:
	.functype	sbb_old (i64, i64, i64, i64) -> (i64)
	.local  	i64, i64
	local.get	3
	local.get	0
	local.get	1
	i64.sub 
	local.tee	4
	local.get	2
	i64.const	63
	i64.shr_s
	local.tee	2
	i64.add 
	local.tee	5
	i64.store	0
	local.get	2
	local.get	0
	local.get	1
	i64.lt_u
	i64.extend_i32_u
	i64.sub 
	local.get	5
	local.get	4
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.section	.text.sqr_new,"",@
	.globl	sqr_new
	.type	sqr_new,@function
sqr_new:
	.functype	sqr_new (i64, i64, i64, i64) -> (i64)
	.local  	i64, i64, i64, i64
	local.get	3
	local.get	1
	i64.const	4294967295
	i64.and 
	local.tee	4
	local.get	1
	i64.const	32
	i64.shr_u
	local.tee	1
	i64.mul 
	local.tee	5
	i64.const	1
	i64.shl 
	i64.const	8589934590
	i64.and 
	local.get	4
	local.get	4
	i64.mul 
	local.tee	4
	i64.const	32
	i64.shr_u
	i64.add 
	local.tee	6
	i64.const	32
	i64.shl 
	local.get	4
	i64.const	4294967293
	i64.and 
	i64.or  
	local.tee	7
	local.get	0
	i64.add 
	local.tee	4
	local.get	2
	i64.add 
	local.tee	0
	i64.store	0
	local.get	5
	i64.const	31
	i64.shr_u
	i64.const	8589934590
	i64.and 
	local.get	1
	local.get	1
	i64.mul 
	i64.add 
	local.get	6
	i64.const	32
	i64.shr_u
	i64.add 
	local.get	4
	local.get	7
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	local.get	0
	local.get	4
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.section	.text.sqr_old,"",@
	.globl	sqr_old
	.type	sqr_old,@function
sqr_old:
	.functype	sqr_old (i64, i64, i64, i64) -> (i64)
	.local  	i64, i64, i64, i64
	local.get	3
	local.get	1
	i64.const	4294967295
	i64.and 
	local.tee	4
	local.get	4
	i64.mul 
	local.tee	5
	i64.const	32
	i64.shr_u
	local.get	1
	i64.const	32
	i64.shr_u
	local.tee	1
	local.get	4
	i64.mul 
	local.tee	4
	i64.add 
	local.tee	6
	i64.const	4294967295
	i64.and 
	local.get	4
	i64.add 
	local.tee	7
	i64.const	32
	i64.shl 
	local.get	5
	i64.const	4294967293
	i64.and 
	i64.or  
	local.tee	5
	local.get	0
	i64.add 
	local.tee	4
	local.get	2
	i64.add 
	local.tee	0
	i64.store	0
	local.get	6
	i64.const	32
	i64.shr_u
	local.get	1
	local.get	1
	i64.mul 
	i64.add 
	local.get	7
	i64.const	32
	i64.shr_u
	i64.add 
	local.get	4
	local.get	5
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	local.get	0
	local.get	4
	i64.lt_u
	i64.extend_i32_u
	i64.add 
	end_function

	.ident	"rustc version 1.99.0-nightly (da86f4d07 2026-07-24)"
	.section	.custom_section.producers,"",@
	.int8	1
	.int8	12
	.ascii	"processed-by"
	.int8	1
	.int8	5
	.ascii	"rustc"
	.int8	37
	.ascii	"1.99.0-nightly (da86f4d07 2026-07-24)"
	.section	.text.sqr_old,"",@
	.section	.custom_section.target_features,"",@
	.int8	9
	.int8	43
	.int8	11
	.ascii	"bulk-memory"
	.int8	43
	.int8	15
	.ascii	"bulk-memory-opt"
	.int8	43
	.int8	22
	.ascii	"call-indirect-overlong"
	.int8	43
	.int8	10
	.ascii	"multivalue"
	.int8	43
	.int8	15
	.ascii	"mutable-globals"
	.int8	43
	.int8	19
	.ascii	"nontrapping-fptoint"
	.int8	43
	.int8	15
	.ascii	"reference-types"
	.int8	43
	.int8	8
	.ascii	"sign-ext"
	.int8	43
	.int8	8
	.ascii	"memory64"
	.section	.text.sqr_old,"",@
