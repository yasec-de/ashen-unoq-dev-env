# Shared helpers for the Ashen demo scripts. Sourced, not executed.

# Narrate a step on the kernel console (the monitor) and in the journal.
# KERN_NOTICE so it still shows when routine kernel chatter is filtered.
say() {
	echo "<5>ashen: $*" > /dev/kmsg
}

die() {
	echo "<3>ashen: FAILED: $*" > /dev/kmsg
	exit 1
}

# wait_for TIMEOUT_S DESCRIPTION CMD...: poll CMD every 0.2 s until it succeeds.
wait_for() {
	local timeout=$1 what=$2 i=0
	shift 2
	until "$@"; do
		i=$((i + 1))
		[ "$i" -ge $((timeout * 5)) ] && die "timed out after ${timeout}s waiting for $what"
		sleep 0.2
	done
}

ashen_dev() {
	local d
	for d in /sys/bus/serial/drivers/ashen-tamper/*/; do
		[ -e "$d/status" ] && { echo "${d%/}"; return 0; }
	done
	return 1
}

# status_field NAME: value of NAME from the driver's status attribute
status_field() {
	awk -v k="$1" '$1 == k { print $2 }' "$ASHEN_DEV/status"
}
