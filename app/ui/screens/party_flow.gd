extends RefCounted
## Navigation state, not transport state. A join remembers where the user started.
enum Page { HOME, LIBRARY, NEARBY, MANUAL, CONNECTING, MATCH }
var page := Page.HOME
var join_origin := Page.NEARBY

func open(next: Page) -> void:
	page = next
	if next in [Page.NEARBY, Page.MANUAL]:
		join_origin = next

func back_target() -> Page:
	match page:
		Page.MANUAL: return Page.NEARBY
		Page.CONNECTING: return join_origin
		_: return Page.HOME

func is_join() -> bool:
	return page in [Page.NEARBY, Page.MANUAL]
