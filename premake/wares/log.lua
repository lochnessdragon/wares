local log = {}

log.info = function(msg)
	term.pushColor(term.lightGreen)
	print("[wares]: " .. msg)
	term.popColor()
end

log.warn = function(msg)
	term.pushColor(term.warningColor)
	print("[wares/warn]: " .. msg)
	term.popColor()
end

log.error = function(msg)
	term.pushColor(term.errorColor)
	print("[wares/error]: " .. msg)
	term.popColor()
end

return log