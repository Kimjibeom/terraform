// main.go (전체 흐름 주석 추가 버전)

// 이 파일은 웹 서버를 실행하는 Go 애플리케이션의 메인 파일입니다.
package main

// 애플리케이션에 필요한 표준 라이브러리 및 외부 라이브러리를 가져옵니다.
import (
	"crypto/rand"     // 암호학적으로 안전한 랜덤 숫자 생성기 (세션 ID 생성에 사용)
	"encoding/base64" // 바이너리 데이터를 텍스트(Base64)로 인코딩 (세션 ID를 쿠키 값으로 만들기 위해 사용)
	"encoding/json"   // JSON 데이터 처리
	"fmt"             // 포맷팅된 문자열 출력 (화면 출력 및 에러 메시지 생성에 사용)
	"io"              // 데이터 입출력 유틸리티 (HTTP 응답 바디를 읽기 위해 사용)
	"log"             // 로깅 기능
	"net/http"        // HTTP 클라이언트 및 서버 기능
	"net/url"         // URL 파싱 및 생성
	"strings"         // 문자열 처리
	"sync"            // 동시성 제어 (여러 요청이 동시에 세션 맵에 접근하는 것을 막기 위해 사용)
	"time"            // 시간 관련 기능 (쿠키 만료 시간 설정에 사용)

	// 외부 JWT 라이브러리. ID Token을 파싱하기 위해 사용합니다.
	"github.com/golang-jwt/jwt/v5"
)

// 애플리케이션 전체에서 사용될 설정 값들을 상수로 정의합니다.
const (
	// ORY Hydra에 등록한 이 애플리케이션의 클라이언트 ID
	hydraClientID = "e7d8954d-0d8e-49a4-a1b4-8d1a4792fc86"
	// ORY Hydra에 등록한 이 애플리케이션의 클라이언트 Secret
	hydraClientSecret = "KflxU9-~hg.u9C-HW_uuNmpI7T"
	// ORY Hydra에서 인증 성공 후 사용자를 돌려보낼 이 애플리케이션의 주소(Callback URL)
	hydraRedirectURI = "http://localhost:3000/callback"
	// ORY Hydra의 공개(Public) API 엔드포인트 주소
	hydraPublicURL = "https://sscr.io/ory/hydra/public"
	// ORY Kratos의 공개(Public) API 엔드포인트 주소
	kratosPublicURL = "https://sscr.io/ory/kratos/public"
	// ORY Kratos의 관리(Admin) API 엔드포인트 주소 (서버 간 통신용)
	kratosAdminURL = "https://sscr.io/ory/kratos/admin"
	// 이 애플리케이션이 실행될 포트 번호
	appPort = ":3000"
)

// 로그인한 사용자의 세션 정보를 저장하기 위한 구조체 정의
type Session struct {
	Role  string // 사용자의 역할 (예: "admin", "user")
	Email string // 사용자의 이메일
}

// 애플리케이션 전역에서 사용될 변수들을 정의합니다.
var (
	// 세션을 저장할 인메모리 맵. key는 랜덤 세션 ID, value는 Session 구조체입니다.
	// 서버가 재시작되면 모든 내용이 사라집니다. (프로토타입용)
	sessionStore = make(map[string]Session)
	// 여러 요청이 동시에 sessionStore 맵에 접근할 때 데이터가 깨지는 것을 방지하는 잠금(Lock) 장치입니다.
	sessionMutex = &sync.RWMutex{}
)

// ORY Hydra의 토큰 엔드포인트 응답을 담기 위한 구조체 정의
type TokenResponse struct {
	AccessToken string `json:"access_token"` // API 접근 시 사용할 액세스 토큰
	IDToken     string `json:"id_token"`     // 사용자 정보(특히 ID)가 담긴 ID 토큰
}

// ORY Kratos의 Admin API에서 받아온 사용자(Identity) 정보를 담기 위한 구조체 정의
type KratosIdentity struct {
	ID     string `json:"id"` // Kratos가 관리하는 사용자의 고유 ID
	Traits struct { // Kratos에 정의된 사용자의 커스텀 속성들
		Email string `json:"email"` // 이메일
		Name  string `json:"name"`  // 이름
		Role  string `json:"role"`  // 역할
	} `json:"traits"`
}

// 애플리케이션의 시작점(Entrypoint)이 되는 main 함수입니다.
func main() {
	// 새로운 HTTP 요청 라우터(경로 분배기)를 생성합니다.
	mux := http.NewServeMux()

	// 각 URL 경로(Path)에 어떤 함수(Handler)가 응답할지 등록합니다.
	mux.HandleFunc("/", homeHandler)         // 홈페이지
	mux.HandleFunc("/login", loginHandler)     // 로그인 시작
	mux.HandleFunc("/callback", callbackHandler) // 로그인 후 콜백 처리
	mux.HandleFunc("/profile", profileHandler)   // 로그인한 사용자의 프로필 페이지
	mux.HandleFunc("/logout", logoutHandler)    // 로그아웃

	// 서버 시작을 알리는 메시지를 콘솔에 출력합니다.
	fmt.Printf("✅ Go 애플리케이션 서버가 http://localhost%s 에서 실행됩니다.\n", appPort)
	// 지정된 포트로 웹 서버를 시작하고 요청을 기다립니다.
	if err := http.ListenAndServe(appPort, mux); err != nil {
		// 만약 서버 시작에 실패하면 (예: 포트가 이미 사용 중), 에러 로그를 남기고 프로그램을 즉시 종료합니다.
		log.Fatalf("FATAL: 서버 시작에 실패했습니다: %s", err)
	}
}

// "/callback" 경로를 처리하는 핸들러 함수. OAuth2/OIDC 흐름의 핵심입니다.
func callbackHandler(w http.ResponseWriter, r *http.Request) {
	// 1. URL 쿼리 파라미터에서 'code'(인가 코드) 값을 가져옵니다.
	code := r.URL.Query().Get("code")
	// 만약 code가 없다면, 에러를 응답하고 함수를 종료합니다.
	if code == "" {
		http.Error(w, "필수 파라미터 'code'가 없습니다.", http.StatusBadRequest)
		return
	}

	// 2. 받아온 'code'를 사용해 토큰을 받아오는 함수를 호출합니다.
	tokenResp, err := exchangeCodeForToken(code)
	if err != nil {
		// 토큰 교환에 실패하면, 서버 에러를 응답하고 함수를 종료합니다.
		http.Error(w, fmt.Sprintf("토큰 교환 실패: %v", err), http.StatusInternalServerError)
		return
	}

	// 3. 토큰 응답에 포함된 'IDToken'에서 Kratos 사용자 ID를 추출하는 함수를 호출합니다.
	kratosID, err := getKratosIDFromIDToken(tokenResp.IDToken)
	if err != nil {
		// IDToken 파싱에 실패하면, 서버 에러를 응답하고 함수를 종료합니다.
		http.Error(w, fmt.Sprintf("ID Token 파싱 실패: %v", err), http.StatusInternalServerError)
		return
	}

	// 4. 추출한 Kratos 사용자 ID로 Kratos Admin API를 호출하여 전체 사용자 정보를 가져옵니다.
	identity, err := getIdentityFromKratos(kratosID)
	if err != nil {
		// 사용자 정보 조회에 실패하면, 서버 에러를 응답하고 함수를 종료합니다.
		http.Error(w, fmt.Sprintf("Kratos에서 Identity 조회 실패: %v", err), http.StatusInternalServerError)
		return
	}

	// 5. 조회한 사용자 정보(역할, 이메일)로 새로운 세션을 생성하는 함수를 호출합니다.
	sessionID, err := createNewSession(identity.Traits.Role, identity.Traits.Email)
	if err != nil {
		// 세션 생성에 실패하면, 서버 에러를 응답하고 함수를 종료합니다.
		http.Error(w, "세션 생성 실패", http.StatusInternalServerError)
		return
	}

	// 6. 생성된 세션 ID를 'session_id'라는 이름의 쿠키에 담아 사용자 브라우저에 저장하도록 응답 헤더를 설정합니다.
	// Path="/": 사이트 전체에서 쿠키 사용, HttpOnly=true: JavaScript로 쿠키 접근 방지(보안), Expires: 쿠키 만료 시간(24시간)
	http.SetCookie(w, &http.Cookie{Name: "session_id", Value: sessionID, Path: "/", HttpOnly: true, Expires: time.Now().Add(24 * time.Hour)})
	// 7. 모든 작업이 완료되었으므로, 사용자를 '/profile' 페이지로 리디렉션시킵니다.
	http.Redirect(w, r, "/profile", http.StatusFound)
}

// ID Token(JWT 문자열)을 파싱하여 Kratos User ID (sub 클레임)를 반환하는 함수
func getKratosIDFromIDToken(idTokenStr string) (string, error) {
	// 경고: 이 코드는 토큰의 서명을 검증하지 않습니다. 테스트 목적으로만 사용해야 합니다.
	// 토큰의 Payload(내용물) 부분만 디코딩하여 값을 확인합니다.
	token, _, err := new(jwt.Parser).ParseUnverified(idTokenStr, jwt.MapClaims{})
	if err != nil {
		// JWT 문자열 형식이 올바르지 않으면 에러를 반환합니다.
		return "", fmt.Errorf("JWT 파싱 실패: %w", err)
	}

	// 토큰의 내용을 키-값 형태의 맵으로 변환합니다.
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		// 변환에 실패하면 에러를 반환합니다.
		return "", fmt.Errorf("JWT claims를 읽을 수 없음")
	}

	// 맵에서 'sub'(Subject, 주체) 키에 해당하는 값을 가져옵니다. 이 값이 바로 Kratos 사용자 ID입니다.
	sub, ok := claims["sub"].(string)
	if !ok {
		// 'sub' 클레임이 없거나 문자열이 아니면 에러를 반환합니다.
		return "", fmt.Errorf("JWT 'sub' 클레임이 없거나 문자열이 아님")
	}
	// 성공적으로 추출한 사용자 ID를 반환합니다.
	return sub, nil
}

// Kratos 사용자 ID를 받아 Kratos Admin API를 호출하여 전체 Identity 정보를 가져오는 함수
func getIdentityFromKratos(kratosID string) (*KratosIdentity, error) {
	// Kratos의 특정 사용자 정보를 조회하는 Admin API 엔드포인트로 GET 요청을 생성합니다.
	req, err := http.NewRequest("GET", kratosAdminURL+"/identities/"+kratosID, nil)
	if err != nil {
		// 요청 생성에 실패하면 에러를 반환합니다.
		return nil, fmt.Errorf("Kratos 요청 생성 실패: %w", err)
	}
	// 참고: 실제 운영 환경의 Kratos Admin API가 인증을 요구한다면, 여기에 인증 헤더를 추가해야 합니다.
	// 예: req.Header.Add("Authorization", "Bearer <your_kratos_api_key>")

	// 생성한 HTTP 요청을 실행합니다.
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		// 네트워크 오류 등으로 요청 실행에 실패하면 에러를 반환합니다.
		return nil, fmt.Errorf("Kratos 요청 실패: %w", err)
	}
	// 함수 종료 시 반드시 응답 바디를 닫아주어 리소스 유출을 방지합니다.
	defer resp.Body.Close()

	// 응답 바디를 []byte 형태로 모두 읽어옵니다.
	body, _ := io.ReadAll(resp.Body)
	// 응답 상태 코드가 200 OK가 아니면 에러를 반환합니다.
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Kratos Identity 조회 실패 - 상태 코드: %d, 응답: %s", resp.StatusCode, string(body))
	}

	// 읽어온 JSON 응답 바디를 우리가 정의한 KratosIdentity 구조체로 변환(Unmarshal)합니다.
	var identity KratosIdentity
	if err := json.Unmarshal(body, &identity); err != nil {
		// JSON 파싱에 실패하면 에러를 반환합니다.
		return nil, fmt.Errorf("Kratos Identity 응답 파싱 실패: %w", err)
	}
	// 성공적으로 변환된 Identity 구조체 포인터를 반환합니다.
	return &identity, nil
}

// "/" 경로를 처리하는 핸들러 함수
func homeHandler(w http.ResponseWriter, r *http.Request) {
	// 응답의 컨텐츠 타입을 HTML로 설정합니다.
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	// 요청에서 'session_id' 쿠키를 읽어옵니다.
	_, err := r.Cookie("session_id")

	// 화면에 표시할 HTML 내용을 담을 변수
	var htmlContent string
	// 쿠키를 읽어오는 데 에러가 발생했다면 (보통 쿠키가 없는 경우), 비로그인 상태로 간주합니다.
	if err != nil {
		htmlContent = `<h1>ORY 연동 Go 애플리케이션</h1><p><a href="/login">로그인 시작하기</a></p>`
	} else {
		// 쿠키가 있다면, 로그인 상태로 간주합니다.
		htmlContent = `<h1>ORY 연동 Go 애플리케이션</h1><p>로그인 된 상태입니다.</p><p><a href="/profile">프로필 보기</a></p><p><a href="/logout">로그아웃</a></p>`
	}
	// 최종 HTML 내용을 생성하고 사용자에게 응답합니다.
	fmt.Fprint(w, generatePage("홈", htmlContent))
}

// "/login" 경로를 처리하는 핸들러 함수
func loginHandler(w http.ResponseWriter, r *http.Request) {
	// ORY Hydra의 인증 엔드포인트 URL을 파싱하여 기본 구조를 만듭니다.
	authURL, _ := url.Parse(hydraPublicURL + "/oauth2/auth")
	// URL에 추가할 쿼리 파라미터들을 생성합니다.
	params := url.Values{}
	params.Add("client_id", hydraClientID)         // 이 앱의 클라이언트 ID
	params.Add("redirect_uri", hydraRedirectURI)  // 로그인 후 돌아올 주소
	params.Add("response_type", "code")           // 인가 코드를 받겠다는 의미
	params.Add("scope", "openid profile offline_access") // 요청할 사용자 정보의 범위
	params.Add("state", "a-random-state-string-for-csrf-protection") // CSRF 공격 방지를 위한 값 (실제로는 랜덤 생성 필요)

	// 생성된 파라미터를 URL에 추가합니다.
	authURL.RawQuery = params.Encode()
	// 완성된 인증 URL로 사용자를 리디렉션시킵니다.
	http.Redirect(w, r, authURL.String(), http.StatusTemporaryRedirect)
}

// "/profile" 경로를 처리하는 핸들러 함수
func profileHandler(w http.ResponseWriter, r *http.Request) {
	// 요청에서 'session_id' 쿠키를 읽어옵니다.
	cookie, err := r.Cookie("session_id")
	if err != nil {
		// 쿠키가 없다면 비로그인 상태이므로 홈페이지로 리디렉션합니다.
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}

	// sessionStore 맵을 읽기 전에 읽기 잠금(Read Lock)을 걸어 동시성 문제를 방지합니다.
	sessionMutex.RLock()
	// 쿠키 값(세션 ID)을 key로 사용하여 세션 저장소에서 세션 정보를 가져옵니다.
	session, ok := sessionStore[cookie.Value]
	// 읽기가 끝났으므로 잠금을 해제합니다.
	sessionMutex.RUnlock()

	// 세션 저장소에 해당 세션 ID가 없다면 (유효하지 않은 쿠키), 홈페이지로 리디렉션합니다.
	if !ok {
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}

	// 화면에 표시할 환영 메시지를 담을 변수
	var welcomeMessage string
	// 세션에 저장된 역할(Role)에 따라 다른 메시지를 설정합니다.
	if session.Role == "admin" {
		welcomeMessage = "Hello World!"
	} else if session.Role == "user" {
		welcomeMessage = "당신은 user입니다."
	} else {
		welcomeMessage = "알 수 없는 역할의 사용자입니다."
	}
	// 최종적으로 사용자에게 보여줄 HTML 메시지를 생성합니다.
	finalMessage := fmt.Sprintf("<h1>%s</h1><p>로그인된 이메일: %s</p>", welcomeMessage, session.Email)
	// 완성된 HTML 페이지를 사용자에게 응답합니다.
	fmt.Fprint(w, generatePage("프로필", finalMessage))
}

// "/logout" 경로를 처리하는 핸들러 함수
func logoutHandler(w http.ResponseWriter, r *http.Request) {
	// 요청에서 'session_id' 쿠키를 읽어옵니다.
	cookie, err := r.Cookie("session_id")
	// 쿠키가 있는 경우에만 세션 정리 작업을 수행합니다.
	if err == nil {
		// sessionStore 맵을 수정하기 전에 쓰기 잠금(Write Lock)을 겁니다.
		sessionMutex.Lock()
		// 서버의 세션 저장소에서 해당 세션 정보를 삭제합니다.
		delete(sessionStore, cookie.Value)
		// 쓰기가 끝났으므로 잠금을 해제합니다.
		sessionMutex.Unlock()

		// 브라우저에게 해당 쿠키를 즉시 삭제(만료)시키라는 응답 헤더를 설정합니다.
		http.SetCookie(w, &http.Cookie{Name: "session_id", Value: "", Path: "/", MaxAge: -1})
	}
	// 우리 앱의 세션 정리가 끝나면, ORY의 글로벌 로그아웃을 위해 해당 URL로 리디렉션합니다.
	logoutURL := kratosPublicURL + "/self-service/logout/browser"
	http.Redirect(w, r, logoutURL, http.StatusTemporaryRedirect)
}

// 새로운 세션을 생성하고 저장하는 헬퍼 함수
func createNewSession(role, email string) (string, error) {
	// 32바이트 길이의 암호학적으로 안전한 랜덤 바이트 슬라이스를 생성합니다.
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		// 랜덤 생성에 실패하면 에러를 반환합니다.
		return "", err
	}
	// 랜덤 바이트를 URL에 사용하기 안전한 Base64 문자열로 인코딩하여 세션 ID로 사용합니다.
	sessionID := base64.URLEncoding.EncodeToString(b)

	// sessionStore 맵을 수정하기 위해 쓰기 잠금을 겁니다.
	sessionMutex.Lock()
	// 맵에 새로운 세션 ID와 사용자 정보를 저장합니다.
	sessionStore[sessionID] = Session{Role: role, Email: email}
	// 쓰기가 끝났으므로 잠금을 해제합니다.
	sessionMutex.Unlock()

	// 서버 로그에 로그인 성공 기록을 남깁니다.
	log.Printf("INFO: 사용자 '%s' 로그인 성공, 역할(role): '%s'", email, role)
	// 생성된 세션 ID와 nil 에러를 반환합니다.
	return sessionID, nil
}

// 인가 코드(Authorization Code)를 토큰(Access Token, ID Token)으로 교환하는 헬퍼 함수
func exchangeCodeForToken(code string) (*TokenResponse, error) {
	// Hydra의 토큰 엔드포인트에 보낼 POST 요청의 본문 데이터를 생성합니다. (x-www-form-urlencoded 형식)
	data := url.Values{}
	data.Set("grant_type", "authorization_code")
	data.Set("code", code)
	data.Set("redirect_uri", hydraRedirectURI)

	// HTTP POST 요청 객체를 생성합니다.
	req, err := http.NewRequest("POST", hydraPublicURL+"/oauth2/token", strings.NewReader(data.Encode()))
	if err != nil { return nil, err }
	// 요청 헤더에 컨텐츠 타입을 명시합니다.
	req.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	// HTTP Basic 인증 헤더를 설정합니다. (사용자 이름: client_id, 비밀번호: client_secret)
	req.SetBasicAuth(hydraClientID, hydraClientSecret)

	// 생성한 요청을 실행합니다.
	resp, err := http.DefaultClient.Do(req)
	if err != nil { return nil, err }
	// 함수 종료 시 응답 바디를 닫습니다.
	defer resp.Body.Close()

	// 응답 바디를 읽어옵니다.
	body, _ := io.ReadAll(resp.Body)
	// 응답 상태 코드가 200 OK가 아니면 에러를 반환합니다.
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("토큰 발급 실패: %s", string(body)) }

	// JSON 응답 바디를 TokenResponse 구조체로 변환합니다.
	var tokenResp TokenResponse
	err = json.Unmarshal(body, &tokenResp)
	// 변환된 구조체 포인터와 nil 에러를 반환합니다.
	return &tokenResp, err
}

// 간단한 HTML 페이지 레이아웃을 생성하는 헬퍼 함수
func generatePage(title, body string) string {
	// fmt.Sprintf를 사용해 HTML 템플릿에 제목과 본문을 채워넣어 최종 HTML 문자열을 반환합니다.
	return fmt.Sprintf(`<!DOCTYPE html><html><head><title>%s</title><style>body { font-family: sans-serif; text-align: center; margin-top: 5rem; } h1 { color: #333; } p { margin-top: 1rem; } a { color: #007bff; }</style></head><body>%s</body></html>`, title, body)
}