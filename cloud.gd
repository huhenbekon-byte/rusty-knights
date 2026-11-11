extends Node
## Облачные аккаунты на Firebase (через REST, без плагинов).
## Вход и регистрация — Firebase Authentication (почта + пароль),
## прогресс — Realtime Database в users/<uid>. Сохраняется сам через 2 с после изменений.
## Вход запоминается: при следующем запуске игра входит сама и подтягивает облако.

# ---- ВСТАВЬ СВОИ КЛЮЧИ FIREBASE (это не секрет: ключ лишь называет проект, защищают правила базы)
const API_KEY := "AIzaSyAfVcN1btMEzuyoOb6S8v-4TT0ZJW_m8aw"      # Настройки проекта → Общие → «Web API Key»
const DB_URL := "https://rusty-knights-default-rtdb.europe-west1.firebasedatabase.app"       # Realtime Database, адрес вверху, например https://xxx-default-rtdb.europe-west1.firebasedatabase.app

const AUTH_PATH := "user://auth.json"
const AUTH_URL := "https://identitytoolkit.googleapis.com/v1/accounts:"
const TOKEN_URL := "https://securetoken.googleapis.com/v1/token?key="

signal status_changed

var uid := ""
var email := ""
var id_token := ""
var refresh_token := ""
var token_time := 0.0
var status := ""         # "" | "sync" — идёт обмен | "ok" — сохранено | "error" — нет связи
var last_error := ""
var _dirty := false
var _save_t := 0.0
var _busy := false
var _applying := false


func configured() -> bool:
	return (API_KEY != "" and DB_URL != "") or "--fakecloud" in OS.get_cmdline_user_args()


func logged_in() -> bool:
	return uid != ""


func _ready() -> void:
	Profile.changed.connect(_on_profile_changed)
	_load_auth()
	if logged_in() and configured():
		sync_on_start()


func _process(delta: float) -> void:
	if _dirty and logged_in() and configured() and not _busy:
		_save_t -= delta
		if _save_t <= 0.0:
			_dirty = false
			upload()


func _on_profile_changed() -> void:
	if _applying:
		return
	_dirty = true
	_save_t = 2.0


func _set_status(s: String) -> void:
	status = s
	status_changed.emit()


# ---------------------------------------------------------------- запросы

func _req(url: String, method: int, body = null, form := false) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = 15.0
	add_child(h)
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded" if form else "Content-Type: application/json"])
	var data := ""
	if body != null:
		data = body if form else JSON.stringify(body)
	var err := h.request(url, headers, method, data)
	if err != OK:
		h.queue_free()
		return {"ok": false, "error": "NET"}
	var res: Array = await h.request_completed
	h.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": "NET"}
	var code := int(res[1])
	var text := (res[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text) if text != "" else null
	if code >= 200 and code < 300:
		return {"ok": true, "data": parsed}
	var msg := "HTTP %d" % code
	if parsed is Dictionary and parsed.has("error"):
		var e = parsed.error
		msg = str(e.get("message", msg)) if e is Dictionary else str(e)
	return {"ok": false, "error": msg, "code": code}


## Понятный текст ошибки Firebase.
func error_text(code: String) -> String:
	if code == "NET":
		return "Нет связи с сервером. Проверь интернет."
	if code.begins_with("EMAIL_EXISTS"):
		return "Такая почта уже зарегистрирована. Попробуй войти."
	if code.begins_with("INVALID_EMAIL"):
		return "Почта написана с ошибкой."
	if code.begins_with("WEAK_PASSWORD"):
		return "Пароль слишком простой: нужно минимум 6 символов."
	if code.begins_with("INVALID_LOGIN_CREDENTIALS") or code.begins_with("INVALID_PASSWORD") or code.begins_with("EMAIL_NOT_FOUND"):
		return "Неверная почта или пароль."
	if code.begins_with("USER_DISABLED"):
		return "Этот аккаунт отключён."
	if code.begins_with("TOO_MANY_ATTEMPTS"):
		return "Слишком много попыток. Подожди немного."
	if code.begins_with("MISSING_PASSWORD"):
		return "Введи пароль."
	if code.begins_with("Permission denied") or code == "HTTP 401":
		return "Сервер не пустил. Проверь правила базы Firebase."
	if code.begins_with("CONFIGURATION_NOT_FOUND") or code.begins_with("OPERATION_NOT_ALLOWED"):
		return "В Firebase не включён вход по почте и паролю."
	return "Ошибка: " + code


# ---------------------------------------------------------------- вход

## Регистрация: создаёт аккаунт и переносит в облако текущий прогресс. Пусто — успех, иначе текст ошибки.
func sign_up(mail: String, password: String) -> String:
	if not configured():
		return "Облако ещё не подключено."
	var r := await _req(AUTH_URL + "signUp?key=" + API_KEY, HTTPClient.METHOD_POST,
		{"email": mail, "password": password, "returnSecureToken": true})
	if not r.ok:
		return error_text(r.error)
	_take(r.data)
	await upload()
	return ""


## Вход: если в облаке есть прогресс — он загружается, иначе туда отправляется текущий.
func sign_in(mail: String, password: String) -> String:
	if not configured():
		return "Облако ещё не подключено."
	var r := await _req(AUTH_URL + "signInWithPassword?key=" + API_KEY, HTTPClient.METHOD_POST,
		{"email": mail, "password": password, "returnSecureToken": true})
	if not r.ok:
		return error_text(r.error)
	_take(r.data)
	var cloud = await download()
	if cloud is Dictionary and not (cloud as Dictionary).is_empty():
		_apply(cloud)
	elif cloud != null or status != "error":
		await upload()
	return ""


## Письмо для сброса пароля.
func reset_password(mail: String) -> String:
	if not configured():
		return "Облако ещё не подключено."
	var r := await _req(AUTH_URL + "sendOobCode?key=" + API_KEY, HTTPClient.METHOD_POST,
		{"requestType": "PASSWORD_RESET", "email": mail})
	return "" if r.ok else error_text(r.error)


func sign_out() -> void:
	uid = ""
	email = ""
	id_token = ""
	refresh_token = ""
	_dirty = false
	if FileAccess.file_exists(AUTH_PATH):
		DirAccess.remove_absolute(AUTH_PATH)
	_set_status("")


func _take(d: Dictionary) -> void:
	uid = str(d.get("localId", d.get("user_id", uid)))
	email = str(d.get("email", email))
	id_token = str(d.get("idToken", d.get("id_token", "")))
	refresh_token = str(d.get("refreshToken", d.get("refresh_token", refresh_token)))
	token_time = Time.get_unix_time_from_system()
	_save_auth()
	status_changed.emit()


## Токен живёт час — обновляем заранее.
func _ensure_token(force := false) -> bool:
	if not force and id_token != "" and Time.get_unix_time_from_system() - token_time < 3000.0:
		return true
	var r := await _req(TOKEN_URL + API_KEY, HTTPClient.METHOD_POST,
		"grant_type=refresh_token&refresh_token=" + refresh_token.uri_encode(), true)
	if not r.ok:
		last_error = error_text(r.error)
		if r.error != "NET":                  # вход отозван — выходим
			sign_out()
		return false
	_take(r.data)
	return true


func _save_auth() -> void:
	var f := FileAccess.open(AUTH_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"uid": uid, "email": email, "refresh": refresh_token}))


func _load_auth() -> void:
	if not FileAccess.file_exists(AUTH_PATH):
		return
	var f := FileAccess.open(AUTH_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		uid = str(d.get("uid", ""))
		email = str(d.get("email", ""))
		refresh_token = str(d.get("refresh", ""))


# ---------------------------------------------------------------- прогресс

func _user_url() -> String:
	return "%s/users/%s.json?auth=%s" % [DB_URL.trim_suffix("/"), uid, id_token]


## Отправить прогресс в облако.
func upload() -> bool:
	if not logged_in() or not configured() or _busy:
		return false
	_busy = true
	_set_status("sync")
	var ok := await _ensure_token()
	if ok:
		var r := await _req(_user_url(), HTTPClient.METHOD_PUT, Profile.data)
		if not r.ok and int(r.get("code", 0)) == 401 and await _ensure_token(true):
			r = await _req(_user_url(), HTTPClient.METHOD_PUT, Profile.data)
		ok = r.ok
		if not ok:
			last_error = error_text(r.error)
	_busy = false
	_set_status("ok" if ok else "error")
	if not ok:
		_dirty = true                         # попробуем снова позже
		_save_t = 20.0
	return ok


## Скачать прогресс из облака (null — нет связи, {} — пусто).
func download():
	if not logged_in() or not configured():
		return null
	_set_status("sync")
	if not await _ensure_token():
		_set_status("error")
		return null
	var r := await _req(_user_url(), HTTPClient.METHOD_GET)
	if not r.ok:
		last_error = error_text(r.error)
		_set_status("error")
		return null
	_set_status("ok")
	return r.data if r.data is Dictionary else {}


## При запуске: берём то сохранение, что новее (облако или телефон).
func sync_on_start() -> void:
	var cloud = await download()
	if cloud == null:
		return
	var cloud_t := float((cloud as Dictionary).get("saved_at", 0.0))
	var local_t := float(Profile.data.get("saved_at", 0.0))
	if not (cloud as Dictionary).is_empty() and cloud_t > local_t:
		_apply(cloud)
	elif local_t > cloud_t or (cloud as Dictionary).is_empty():
		await upload()


func _apply(cloud: Dictionary) -> void:
	_applying = true
	Profile.apply_dict(cloud)
	Profile.save(false)
	_applying = false
	_set_status("ok")
