### 后续实验需要注意的

* 异常使用ebus[15:0]沿着流水级传递，异常使用独热码表示

  后续要添加异常时可以参考以下代码:

  ```verilog
  assign has_sys = inst_syscall;
  assign ebus_end = ebus_init | {{15-`EBUS_SYS{1'b0}}, has_sys, {`EBUS_SYS{1'b0}}};
  ```

  最后在写回级再选出优先级最高的那个异常

* 关于时间的csr寄存器暂时注释掉了，从讲义cv的，不保证正确性(
