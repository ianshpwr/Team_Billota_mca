#!/usr/bin/env python3
"""Mutation check: inject known bugs into COPIES of the RTL and confirm the
testbench fails for each one (a surviving mutant = a testbench coverage gap).
Usage: python3 -I scripts/mutation_check.py [repo_root] [work_dir]"""

import subprocess, shutil, os, sys
root=sys.argv[1] if len(sys.argv)>1 else "."; work=sys.argv[2] if len(sys.argv)>2 else "build/mutants"
muts=[
 ("M1 byte order reversed on read", "rtl/cache_memory.v", "assign byte_o  = block_o[{offset, 3'b000} +: 8];", "assign byte_o  = block_o[{~offset, 3'b000} +: 8];"),
 ("M2 valid bit ignored in hit", "rtl/cache_controller.v", "wire hit       = cache_valid && tag_match;", "wire hit       = tag_match;"),
 ("M3 tag compare drops MSB", "rtl/cache_controller.v", "wire tag_match = (cache_tag == req_tag);", "wire tag_match = (cache_tag[8:0] == req_tag[8:0]);"),
 ("M4 byte write clobbers whole word", "rtl/cache_memory.v", "data_array[index]  <= merge_byte(data_array[index], offset, byte_wdata);", "data_array[index]  <= {4{byte_wdata}};"),
 ("M5 response without waiting for memory (read)", "rtl/cache_controller.v", "if (mem_done) next_state = S_REFILL;", "next_state = S_REFILL;"),
 ("M6 refill tag not updated", "rtl/cache_memory.v", "tag_array[index]   <= refill_tag;", "tag_array[index]   <= tag_array[index];"),
 ("M7 write-through skipped (hit path jumps to RESPONSE)", "rtl/cache_controller.v", "S_WRITE_HIT:         next_state = S_MEMORY_WRITE_WAIT;", "S_WRITE_HIT:         next_state = S_RESPONSE;"),
 ("M8 memory block read unaligned (no addr mask)", "rtl/cache_controller.v", "assign mem_addr  = mem_we ? req_addr : {req_addr[15:2], 2'b00};", "assign mem_addr  = req_addr;"),
 ("M9 memory big-endian block assembly", "rtl/main_memory.v", "{ mem[blk_base + 16'd3], mem[blk_base + 16'd2],\n                                 mem[blk_base + 16'd1], mem[blk_base] }", "{ mem[blk_base], mem[blk_base + 16'd1],\n                                 mem[blk_base + 16'd2], mem[blk_base + 16'd3] }"),
 ("M10 stale rdata (not cleared, read bypass from old reg)", "rtl/cache_controller.v", "if (state == S_READ_HIT)\n                rdata_reg <= cache_byte;", "if (state == S_COMPARE_TAG)\n                rdata_reg <= cache_byte;"),
 ("M11 write-allocate skips refill (write miss writes straight)", "rtl/cache_controller.v", "S_WRITE_MISS:        next_state = S_MEMORY_READ_WAIT;", "S_WRITE_MISS:        next_state = S_WRITE_HIT;"),
 ("M12 reset does not clear valid bits", "rtl/cache_memory.v", "valid_array <= 16'd0;", "valid_array <= valid_array;"),
]
for name,f,old,new in muts:
    d=os.path.join(work,name.split()[0]); shutil.rmtree(d,ignore_errors=True)
    shutil.copytree(os.path.join(root,'rtl'),os.path.join(d,'rtl'))
    p=os.path.join(d,f); s=open(p).read()
    if old not in s: print(name,"-> PATTERN NOT FOUND"); continue
    open(p,'w').write(s.replace(old,new,1))
    rtl=[os.path.join(d,'rtl',x) for x in ['main_memory.v','cache_memory.v','cache_controller.v','cache_top.v']]
    c=subprocess.run(['iverilog','-g2001','-s','cache_tb','-o',d+'/s.vvp',os.path.join(root,'testbench/cache_tb.v')]+rtl,capture_output=True,text=True)
    if c.returncode: print(name,"-> COMPILE ERROR",c.stderr[:200]); continue
    r=subprocess.run(['vvp',d+'/s.vvp','+novcd'],capture_output=True,text=True,cwd=root)
    out=r.stdout
    fails=out.count('[FAIL]'); mons=out.count('[MONITOR ERROR]')
    verdict="DETECTED" if ("ALL TESTS PASSED" not in out) else "*** SURVIVED ***"
    print(f"{name:62s} {verdict:16s} fails={fails} monitor_errors={mons}")
