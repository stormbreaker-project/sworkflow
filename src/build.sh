#!/usr/bin/env bash

#
# Copyright (C) 2019 Saalim Quadri (danascape)
#
# SPDX-License-Identifier: Apache-2.0 license
#

. "$SW_SRC_DIR"/src/build_vars.sh --source-only
. "$SW_SRC_DIR"/src/sw_functions.sh --source-only

# Check if the kernel config already exists for a particular device.
# This check is being performed to add support for official devices.
check_kernel()
{
	#	parse_build_arguments "$1"

	local device
	local device_config_dir
	device="$1"
	device_config_dir="configs"
	log_info "sworkflow: Checking if kernel config exists for $device"
	if [[ -n $(find -L "$SW_SRC_DIR"/"$device_config_dir" -maxdepth 2 -name "sworkflow.$device.config") ]]; then
		for dir in $device_config_dir; do
			for f in $(cd "$SW_SRC_DIR" && test -d "$dir" &&
				find -L "$SW_SRC_DIR" -maxdepth 4 -name "sworkflow.$device.config" | sort); do
				log_info "sworkflow: Including $f"
				. "$f" --source-only
			done
		done
	elif [[ -n $(find -L "$(pwd)" -maxdepth 2 -name "sworkflow.$device.config") ]]; then
		for dir in $device_config_dir; do
			for f in $(cd "$(pwd)" && test -d "$dir" &&
				find -L "$(pwd)" -maxdepth 4 -name "sworkflow.$device.config" | sort); do
				log_info "sworkflow: Including $f"
				. "$f" --source-only
			done
		done
	else
		log_error "error: No config file found"
		log_error "error: Refer to docs for more"
		exit 125
	fi

}

displayDeviceInfo()
{

	if [[ $# = 0 ]]; then
		log_info "usage: displayDeviceInfo [target]" >&2
		return 1
	fi

	local DEVICE
	local TARGET_DEVICE
	local HOST_OS
	local HOST_OS_EXTRA

	DEVICE="$1"
	TARGET_DEVICE="$DEVICE"
	HOST_OS="$(uname)"
	HOST_OS_EXTRA="$(uname -r)"

	log_info "============================================"
	log_info "TARGET_DEVICE=$TARGET_DEVICE"
	log_info "TARGET_ARCH=$device_arch"
	log_info "KERNEL_DEFCONFIG=$kernel_defconfig"
	log_info "KERNEL_DIR=$PWD"
	log_info "HOST_OS=$HOST_OS"
	log_info "HOST_OS_EXTRA=$HOST_OS_EXTRA"
	log_info "HOST_PATH=$PATH"
	log_info "OUT_DIR=out" # HardCode this for now.
	log_info "============================================"
}

kernel_build()
{
	device="$3"
	check_kernel "$device"
	log_info "sworkflow: Starting Kernel Build!"

	if [[ -z "$(command -v nproc)" ]]; then
		parallel_threads="$(nproc --all)"
	else
		parallel_threads="$(grep -c ^processor /proc/cpuinfo)"
	fi

	if ! is_kernel_root "$PWD"; then
		log_error "error: Execute this command in a kernel tree."
		exit 125
	fi

	if [[ -n "$build_silent" ]]; then
		MAKE+=(-s)
	fi

	if [[ -n "$cross_compile" ]]; then
		cross_compile="CROSS_COMPILE=$cross_compile"
		MAKE+=("$cross_compile")
	fi

	if [[ -n "$cross_compile_arm32" ]]; then
		cross_compile_arm32="CROSS_COMPILE_ARM32=$cross_compile_arm32"
		MAKE+=("$cross_compile_arm32")
	fi

	if [[ -n "$use_clang" ]]; then
		cc="CC=clang"
		clang_triple="CLANG_TRIPLE=aarch64-linux-gnu-"
		MAKE+=("$cc"
			"$clang_triple")
	fi

	if [[ -n "$device_arch" ]]; then
		if [[ -n $kernel_arch ]]; then
			if [[ -n "$kernel_defconfig" ]]; then
				if [[ -f arch/"$kernel_arch"/configs/"$kernel_defconfig" ]]; then
					log_info ""
				else
					log_error "error: Device Defconfig not found!"
					exit 22
				fi
			else
				log_error "error: Device Defconfig not defined!"
			fi
		else
			if [[ -n "$kernel_defconfig" ]]; then
				if [[ -f arch/$device_arch/configs/"$kernel_defconfig" ]]; then
					log_info ""
				else
					log_error "error: Device Defconfig not found!"
					exit 22
				fi
			else
				log_error "error: Device Defconfig not defined!"
				exit 22
			fi
		fi
	else
		log_error "error: Device architecture not defined!"
		exit 22
	fi

	displayDeviceInfo "$device"

	make O=out -j"$parallel_threads" ARCH="$device_arch" "${MAKE[@]}" "$kernel_defconfig"

	start=$(date +%s)

	make O=out -j"$parallel_threads" ARCH="$device_arch" "${MAKE[@]}"

	if [[ -n "$create_dtbo" ]]; then
		log_info "sworkflow: Creating dtbo"
		dtbo_path="out/arch/$device_arch/boot/dtbo.img"
		if [[ -f $dtbo_path ]]; then
			log_warning "warning: DTBO image already present!"
		else
			if [[ -n "$dtbo_page_size" ]]; then
				if [[ -n $dtbo_arch_path ]]; then
					python3 "$SW_SRC_DIR"/utils/mkdtboimg.py create "out/arch/$device_arch/boot/dtbo.img" --page_size="$dtbo_page_size" "$dtbo_arch_path"
				else
					log_error "error: kernel DTBO directory not defined!"
					exit 22
				fi
			else
				log_error "error: DTBO page size not defined!"
				exit 22
			fi
		fi
	fi

	end=$(date +%s)

	time=$((end - start))
	elapsed_time=$(date -d@"$time" -u +%H:%M:%S)
	log_info "-> sworkflow: Execution time: $elapsed_time"
}

parse_build_arguments()
{
	if [[ "$?" != 0 ]]; then
		return 22 # EINVAL
	fi

	while [[ "$#" -gt 0 ]]; do
		case "$1" in
			*)
				log_error "error: Invalid Argument"
				exit 22 # EINVAL
				;;
		esac
	done
}
