# Parse `tailscale status --json` into a tab separated stream:
#
#   self|peer <TAB> dns_name <TAB> host_name <TAB> ip [<TAB> ip ...]
#
# The output of `tailscale status --json` is indented JSON (Go's
# json.MarshalIndent), so a small line based parser is enough here.  The
# "Self" and "Peer" root keys tell us which object a HostName belongs to.

function value_of(line,   s) {
	s = line
	sub(/^[^:]*:[ \t]*/, "", s)   # drop   "Key":
	sub(/,[ \t]*$/, "", s)        # drop trailing comma
	sub(/^"/, "", s)              # drop opening quote
	sub(/"$/, "", s)              # drop closing quote
	return s
}

function flush(   tag, i) {
	if (dns != "" && section != "") {
		tag = (section == "self") ? "self" : "peer"
		printf "%s\t%s\t%s", tag, dns, host
		for (i = 0; i < nip; i++)
			printf "\t%s", ip[i]
		printf "\n"
	}
	dns = ""
	host = ""
	nip = 0
	in_ips = 0
}

/^[ \t]*"Self"[ \t]*:[ \t]*\{/ {
	flush()
	section = "self"
	next
}

/^[ \t]*"Peer"[ \t]*:[ \t]*\{/ {
	flush()
	section = "peer"
	next
}

/"HostName"[ \t]*:/ {
	# Flush only once both fields are present, so the parser does not
	# depend on HostName appearing before DNSName in the JSON.
	if (dns != "" && host != "")
		flush()
	host = value_of($0)
	next
}

/"DNSName"[ \t]*:/ {
	if (dns != "" && host != "")
		flush()
	dns = value_of($0)
	sub(/\.$/, "", dns)
	next
}

/"TailscaleIPs"[ \t]*:/ {
	in_ips = 1
	if ($0 ~ /\]/)
		in_ips = 0
	next
}

in_ips && /^[ \t]*\]/ {
	in_ips = 0
	next
}

in_ips {
	if (match($0, /"[^"]+"/))
		ip[nip++] = substr($0, RSTART + 1, RLENGTH - 2)
	next
}

END {
	flush()
}
