.PHONY: clean, check-loader001

check-loader001: linux-e2k-loader-0.01.bin
	sha256sum -c linux-e2k-loader-0.01.sha256

%.bin: %.s
	nasm $< -o $@

clean:
	rm -f *.bin
