onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_elm_accel_completo/clk
add wave -noupdate /tb_elm_accel_completo/reset_n
add wave -noupdate /tb_elm_accel_completo/sw
add wave -noupdate /tb_elm_accel_completo/confirm_btn
add wave -noupdate /tb_elm_accel_completo/prep_btn
add wave -noupdate /tb_elm_accel_completo/result_out
add wave -noupdate /tb_elm_accel_completo/hex3
add wave -noupdate /tb_elm_accel_completo/hex2
add wave -noupdate /tb_elm_accel_completo/hex1
add wave -noupdate /tb_elm_accel_completo/hex0
add wave -noupdate /tb_elm_accel_completo/ledr_pred
add wave -noupdate /tb_elm_accel_completo/ledr_flags
add wave -noupdate /tb_elm_accel_completo/erro_count
add wave -noupdate /tb_elm_accel_completo/ok_count
add wave -noupdate /tb_elm_accel_completo/ultimo_estado
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {16287390269 ps} {16289187111 ps}
