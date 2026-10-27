class_name UIFormat
extends RefCounted
## Formato de números/tiempos para la UI (un solo lugar, en español).

## 1240 → "1.240"
static func number(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## 1240 → "◈ 1.240"
static func coins(n: int) -> String:
	return "%s %s" % [UIStyle.COIN_SYMBOL, number(n)]

## 1452.0 → "24:12" (o "1:02:03" si pasa la hora)
static func time(seconds: float) -> String:
	var total := int(seconds)
	var h := int(total / 3600.0)
	var m := int((total % 3600) / 60.0)
	var sec := total % 60
	if h > 0:
		return "%d:%02d:%02d" % [h, m, sec]
	return "%02d:%02d" % [m, sec]

## 0.25 → "25%"
static func pct(f: float) -> String:
	return "%d%%" % roundi(f * 100.0)

## 2.0 → "×2"; 1.5 → "×1,5" (multiplicadores, con coma decimal).
static func mult(f: float) -> String:
	if is_equal_approx(f, roundf(f)):
		return "×%d" % roundi(f)
	return "×" + ("%.1f" % f).replace(".", ",")

## 8 → "VIII" (rangos, pisos y niveles en placas y encabezados; 1..39).
static func roman(n: int) -> String:
	if n <= 0 or n >= 40:
		return str(n)
	var out := ""
	var rest := n
	for pair: Array in [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]]:
		var value: int = pair[0]
		while rest >= value:
			out += String(pair[1])
			rest -= value
	return out
