`timescale 1ps/1ps

module main();

    initial begin
        $dumpfile("cpu.vcd");
        $dumpvars(0,main);
    end

    // clock
    wire clk;
    clock c0(clk);

    reg halt = 0;

    counter ctr(halt,clk);

    // PC
    reg [15:0]pc = 16'h0000;

    // fetch
    wire [15:1] mem_read1;
    wire [15:0] insFromMem; //instruction out from PC
    wire [15:0] mem_out1; //value out from mem_read1
    reg F_valid = 0;
    reg [15:0]F_pc = 0;

    always @(posedge clk) begin
        F_pc <= pc;
        F_valid <= 1 & ~do_flush;
    end
    
    reg F2_valid = 0;
    reg [15:0]F2_pc = 0;

    always @(posedge clk) begin
        F2_valid <= F_valid & ~do_flush;
        F2_pc <= F_pc;
    end

    //decode

    reg [15:0]D_pc = 0;

    wire [15:0]ins = F2_valid ? insFromMem : 16'h0000;

    wire D_is_sub_wire = ins[15:12] == 4'b0000;
    wire D_is_movl_wire = ins[15:12] == 4'b1000;
    wire D_is_movh_wire = ins[15:12] == 4'b1001;
    wire D_is_jump_wire = ins[15:12] == 4'b1110 & (ins[7:4] == 4'b0000 || ins[7:4] == 4'b0001 || ins[7:4] == 4'b0010 || ins[7:4] == 4'b0011);
    wire D_is_ld_st_wire = ins[15:12] == 4'b1111;

    reg D_valid = 0;

    wire [3:0]D_arg1_wire = D_is_sub_wire || D_is_jump_wire || D_is_ld_st_wire || D_is_ld_st_wire ? ins[11:8] : D_is_movh_wire || D_is_movl_wire ? ins[3:0] : 0; // -1 is an impossible register right
    wire [3:0]D_arg2_wire = D_is_sub_wire ? ins[7:4] : D_is_movh_wire || D_is_movl_wire || D_is_jump_wire || D_is_ld_st_wire || D_is_ld_st_wire ? ins[3:0] : 0;

    wire [7:0]D_literal_wire = ins[11:4];
    wire [3:0]D_jump_io_type_wire = ins[7:4];
    wire [3:0]D_target_wire = ins[3:0];

    wire [15:0]D_reg1_real;
    wire [15:0]D_reg2_real;

    reg [3:0]D_arg1 = 0;
    reg [3:0]D_arg2 = 0;

    reg D_is_sub = 0;
    reg D_is_movl = 0;
    reg D_is_movh = 0;
    reg D_is_jump = 0;
    reg D_is_ld_st = 0;

    reg [7:0]D_literal = 0;
    reg [3:0]D_jump_io_type = 0;
    reg [3:0]D_target = 0;
    
    always @(posedge clk) begin
        D_valid <= F2_valid & ~do_flush;

        D_pc <= F2_pc;
        
        D_arg1 <= D_arg1_wire;
        D_arg2 <= D_arg2_wire;

        D_is_sub <= D_is_sub_wire;
        D_is_movl <= D_is_movl_wire;
        D_is_movh <= D_is_movh_wire;
        D_is_jump <= D_is_jump_wire;
        D_is_ld_st <= D_is_ld_st_wire;

        D_literal <= D_literal_wire;
        D_jump_io_type <= D_jump_io_type_wire;
        D_target <= D_target_wire;
    end    

    // execution

    wire [15:0]X_reg1_wire = D_arg1 == 0 ? 0 : D_reg1_real; //will take an extra cycle to calculate compared to other values like X_literal so it can be a wire
    wire [15:0]X_reg2_wire = D_arg2 == 0 ? 0 : D_reg2_real;
    
    reg [15:0]X_reg1 = 0;
    reg [15:0]X_reg2 = 0;
    
    assign mem_read1 = X_reg1_wire[15:1]; // reading regs[a] from memory

    reg [15:0]X_pc = 0;

    reg [7:0]X_literal = 0;
    reg [3:0]X_jump_io_type = 0;
    reg [3:0]X_target = 0;

    reg X_is_sub = 0;
    reg X_is_movl = 0;
    reg X_is_movh = 0;
    reg X_is_jump = 0; 
    reg X_is_ld_st = 0;

    reg X_valid = 0;

    reg [3:0]X_arg1 = 0;
    reg [3:0]X_arg2 = 0;

    //these wires are all calcluated after reg1 and reg2 are found, which takes a cycle because reading from registers takes a cycle
    wire [15:0]X_sub_result_wire =  X_reg1_wire - X_reg2_wire; 
    wire [15:0]X_movl_result_wire = {{8{D_literal[7]}}, D_literal};
    wire [15:0]X_movh_result_wire = {D_literal , X_reg2_wire[7:0]};
    wire X_jz_taken = X_reg1_wire == 0;
    wire X_jnz_taken = X_reg1_wire != 0;
    wire X_js_taken = X_reg1_wire[15] == 1;
    wire X_jns_taken = X_reg1_wire[15] == 0;
    wire [15:0]X_pc_after_jump_wire = X_reg2_wire;
    wire X_jump_taken_wire = (D_jump_io_type == 4'b0000 && X_jz_taken) || (D_jump_io_type == 4'b0001 && X_jnz_taken) || (D_jump_io_type == 4'b0010 && X_js_taken) || (D_jump_io_type == 4'b0011 && X_jns_taken); //only one of them, if any, can be true;
    
    reg [15:0]X_sub_result = 0;
    reg [15:0]X_movl_result = 0;
    reg [15:0]X_movh_result = 0;
    reg [15:0]X_pc_after_jump = 0;
    reg X_jump_taken = 0;

    always @(posedge clk) begin
        X_pc <= D_pc;
        
        X_valid <= D_valid & ~do_flush;
        X_is_sub <= D_is_sub;
        X_is_movl <= D_is_movl;
        X_is_movh <= D_is_movh;
        X_is_jump <= D_is_jump;
        X_is_ld_st <= D_is_ld_st;

        X_sub_result <= X_sub_result_wire;
        X_movl_result <= X_movl_result_wire;
        X_movh_result <= X_movh_result_wire;
        X_pc_after_jump <= X_pc_after_jump_wire;
        X_jump_taken <= X_jump_taken_wire;

        X_literal <= D_literal;
        X_jump_io_type <= D_jump_io_type;
        X_target <= D_target;

        X_reg1 <= X_reg1_wire;
        X_reg2 <= X_reg2_wire;

        X_arg1 <= D_arg1;
        X_arg2 <= D_arg2;
    end

    // X2

    reg [15:0]X2_pc = 0;

    reg X2_valid = 0;

    reg [3:0]X2_arg1 = 0; //ra
    reg [3:0]X2_arg2 = 0; //rb or rt

    reg [15:0]X2_reg1 = 0;
    reg [15:0]X2_reg2 = 0;

    reg [3:0]X2_jump_io_type = 0;
    reg [3:0]X2_target = 0;
    reg [7:0]X2_literal = 0;

    reg X2_is_sub = 0;
    reg X2_is_movl = 0;
    reg X2_is_movh = 0;
    reg X2_is_jump = 0; 
    reg X2_is_ld_st = 0;

    
    reg [15:0]X2_sub_result = 0;
    reg [15:0]X2_movl_result = 0;
    reg [15:0]X2_movh_result = 0;
    reg [15:0]X2_pc_after_jump = 0;
    reg X2_jump_taken = 0;

    always @(posedge clk) begin
        X2_pc <= X_pc;

        X2_valid <= X_valid & ~do_flush;
        X2_is_sub <= X_is_sub;
        X2_is_movl <= X_is_movl;
        X2_is_movh <= X_is_movh;
        X2_is_jump <= X_is_jump;
        X2_is_ld_st <= X_is_ld_st;

        X2_sub_result <= X_sub_result;
        X2_movl_result <= X_movl_result;
        X2_movh_result <= X_movh_result;
        X2_pc_after_jump <= X_pc_after_jump;
        X2_jump_taken <= X_jump_taken;
        
        X2_jump_io_type <= X_jump_io_type;
        X2_target <= X_target;
        X2_literal <= X_literal;

        X2_arg1 <= X_arg1;
        X2_arg2 <= X_arg2;

        X2_reg1 <= X_reg1;
        X2_reg2 <= X_reg2;
    end

    // write back
    // needs to be regs because mem_out1 won't be ready until now

    wire [15:0]WB_pc = X2_pc;

    wire WB_valid = X2_valid;
    
    wire WB_is_sub = X2_is_sub;
    wire WB_is_movl = X2_is_movl;
    wire WB_is_movh = X2_is_movh;
    wire WB_is_jump = X2_is_jump;
    wire WB_is_ld_st = X2_is_ld_st;
    wire [3:0]WB_jump_io_type = X2_jump_io_type;

    wire [15:0]WB_sub_result = X2_sub_result;
    wire [15:0]WB_movl_result = X2_movl_result;
    wire [15:0]WB_movh_result = X2_movh_result;
    wire [15:0]WB_ld_result = mem_out1;
    wire [15:0]WB_pc_after_jump = X2_pc_after_jump;
    wire WB_jump_taken = X2_jump_taken & WB_valid;

    wire [3:0]WB_arg1 = X2_arg1;
    wire [3:0]WB_arg2 = X2_arg2;
    wire [3:0]WB_target = X2_target;
    
    wire [15:0]WB_reg1 = X2_reg1;
    wire [15:0]WB_reg2 = X2_reg2;

    wire WB_regs_wen = WB_valid && (WB_is_sub || WB_is_movl || WB_is_movh || WB_is_ld_st && (WB_jump_io_type == 4'b0000)); 
    wire WB_mem_wen = WB_valid && (WB_is_ld_st && (WB_jump_io_type == 4'b0001));

    wire [15:1]WB_mem_waddr = WB_reg1[15:1];
    wire [15:0]WB_mem_wdata = WB_reg2;
    wire [3:0]WB_regs_waddr = WB_target;
    wire [15:0]WB_regs_wdata = WB_is_sub == 1 ? WB_sub_result : WB_is_movl == 1 ? WB_movl_result : WB_is_movh == 1 ? WB_movh_result : WB_ld_result;

    wire do_halt = WB_valid & !(X2_is_sub || X2_is_movl || X2_is_movh || X2_is_jump || (X2_is_ld_st && (X2_jump_io_type == 4'b0000 || X2_jump_io_type == 4'b0001)));

    wire do_flush = (WB_is_jump & WB_jump_taken) | (WB_regs_wen | WB_mem_wen) | (WB_valid & do_halt);

    wire [15:0]new_pc = WB_is_jump & WB_jump_taken ? WB_pc_after_jump : do_flush ? WB_pc + 2 : pc + 2;

    always @(posedge clk) begin
        if(WB_regs_wen == 1 && WB_regs_waddr == 0) begin
            $write("%c", WB_regs_wdata);
        end
        
        if(do_halt)begin
            halt <= 1;
        end
    end

    mem mem(clk,
         pc[15:1], insFromMem, mem_read1[15:1], mem_out1, WB_mem_wen, WB_mem_waddr[15:1], WB_mem_wdata);
    
    regs regs(clk,
        D_arg1_wire, D_reg1_real,
        D_arg2_wire, D_reg2_real,
        WB_regs_wen, WB_regs_waddr, WB_regs_wdata);
    

    always @(posedge clk) begin
        //$write("pc = %d\n",pc);
        pc <= new_pc;
    end


endmodule