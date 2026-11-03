# Turn the peer stream from parse-status.awk into /etc/hosts lines.
#
# Options (via -v):
#   self=0|1    include the local node
#   v6=0|1      include IPv6 addresses
#   short=0|1   add MagicDNS short names (first DNS label) and HostName
#
# A short name is dropped when more than one node claims it, because /etc/hosts
# has no priority concept and a wrong answer is worse than no answer.

BEGIN {
	FS = "\t"
}

{
	tag = $1
	dns = $2
	host = $3
	sub(/\.$/, "", dns)
	sub(/\.$/, "", host)

	if (dns == "")
		next
	if (tag == "self" && self == 0)
		next

	n++
	name[n] = dns
	hostname[n] = host

	c = 0
	for (i = 4; i <= NF; i++) {
		ip = $i
		if (ip == "")
			continue
		if (ip ~ /:/ && v6 == 0)
			continue
		addr[n, c++] = ip
	}
	count[n] = c
}

END {
	# Build the alias list for every node.  Index 0 is always the FQDN and
	# is never optional.
	for (i = 1; i <= n; i++) {
		aliases[i, 0] = name[i]
		optional[i, 0] = 0
		k = 1

		if (short == 1) {
			s = name[i]
			sub(/\..*$/, "", s)
			if (s != "" && s != name[i]) {
				aliases[i, k] = s
				optional[i, k] = 1
				k++
			}

			# HostName may be a display name ("OnePlus Ace 6"), so only
			# accept it when it is a legal single DNS label.
			h = hostname[i]
			if (h != "" && h != s && h != name[i] &&
			    h ~ /^[A-Za-z0-9][A-Za-z0-9_-]*$/) {
				aliases[i, k] = h
				optional[i, k] = 1
				k++
			}
		}
		total[i] = k
	}

	# Count optional alias collisions across all nodes.
	for (i = 1; i <= n; i++)
		for (j = 0; j < total[i]; j++)
			if (optional[i, j] == 1)
				uses[aliases[i, j]]++

	for (i = 1; i <= n; i++) {
		line = ""
		for (j = 0; j < total[i]; j++) {
			if (optional[i, j] == 1 && uses[aliases[i, j]] > 1)
				continue
			line = line " " aliases[i, j]
		}
		for (a = 0; a < count[i]; a++)
			print addr[i, a] line
	}
}
