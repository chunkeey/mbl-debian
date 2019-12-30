These are example commands for booting the generated image via the
u-boot prompt through the serial port.

This assumes that the tftp server is located at 192.168.8.7.
The tftp server should have the apollo3g.dtb in the root directory.

---
# sata init; setenv bootargs root=/dev/sda3
# ext2load sata 1:1 ${kernel_addr_r} /uImage; tftp ${fdt_addr_r} 192.168.8.7:/apollo3g.dtb; 
# run boot_args addtty; bootm ${kernel_addr_r} - ${fdt_addr_r}
---
