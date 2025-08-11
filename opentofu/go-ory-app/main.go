package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	hydraClientID       = "e7d8954d-0d8e-49a4-a1b4-8d1a4792fc86"
	hydraClientSecret   = "KflxU9-~hg.u9C-HW_uuNmpI7T"
	hydraRedirectURI    = "http://localhost:3000/callback"
	hydraPublicURL      = "https://sscr.io/ory/hydra/public"
	kratosPublicURL     = "https://sscr.io/ory/kratos/public"
	kratosAdminURL      = "https://sscr.io/ory/kratos/admin"
	appPort             = ":3000"
)

type Session struct {
	Role  string
	Email string
}

var (
	sessionStore = make(map[string]Session)
	sessionMutex = &sync.RWMutex{}
)

type TokenResponse struct {
	AccessToken string `json:"access_token"`
	IDToken     string `json:"id_token"`
}

// Kratos Admin API의 Identity 응답 구조체
type KratosIdentity struct {
	ID     string `json:"id"`
	Traits struct {
		Email string `json:"email"`
		Name  string `json:"name"`
		Role  string `json:"role"`
	} `json:"traits"`
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", homeHandler)
	mux.HandleFunc("/login", loginHandler)
	mux.HandleFunc("/callback", callbackHandler)
	mux.HandleFunc("/profile", profileHandler)
	mux.HandleFunc("/logout", logoutHandler)
	fmt.Printf("✅ Go 애플리케이션 서버가 http://localhost%s 에서 실행됩니다.\n", appPort)
	if err := http.ListenAndServe(appPort, mux); err != nil {
		log.Fatalf("FATAL: 서버 시작에 실패했습니다: %s", err)
	}
}

// callbackHandler를 Kratos Admin API를 사용하도록 수정
func callbackHandler(w http.ResponseWriter, r *http.Request) {
	code := r.URL.Query().Get("code")
	if code == "" {
		http.Error(w, "필수 파라미터 'code'가 없습니다.", http.StatusBadRequest)
		return
	}

	// 1. 토큰 교환
	tokenResp, err := exchangeCodeForToken(code)
	if err != nil {
		http.Error(w, fmt.Sprintf("토큰 교환 실패: %v", err), http.StatusInternalServerError)
		return
	}

	// 2. ID Token에서 사용자 ID (sub) 추출
	kratosID, err := getKratosIDFromIDToken(tokenResp.IDToken)
	if err != nil {
		http.Error(w, fmt.Sprintf("ID Token 파싱 실패: %v", err), http.StatusInternalServerError)
		return
	}

	// 3. Kratos Admin API를 호출하여 전체 Identity 정보 가져오기
	identity, err := getIdentityFromKratos(kratosID)
	if err != nil {
		http.Error(w, fmt.Sprintf("Kratos에서 Identity 조회 실패: %v", err), http.StatusInternalServerError)
		return
	}

	// 4. 세션 생성 및 리디렉션
	sessionID, err := createNewSession(identity.Traits.Role, identity.Traits.Email)
	if err != nil {
		http.Error(w, "세션 생성 실패", http.StatusInternalServerError)
		return
	}

	http.SetCookie(w, &http.Cookie{Name: "session_id", Value: sessionID, Path: "/", HttpOnly: true, Expires: time.Now().Add(24 * time.Hour)})
	http.Redirect(w, r, "/profile", http.StatusFound)
}

// ID Token을 파싱하여 Kratos User ID (sub)를 반환하는 함수
func getKratosIDFromIDToken(idTokenStr string) (string, error) {
	// 서명 검증은 생략하고 Payload만 디코딩 (테스트 목적)
	// 실제 프로덕션에서는 JWKS를 이용해 서명 검증 필요
	token, _, err := new(jwt.Parser).ParseUnverified(idTokenStr, jwt.MapClaims{})
	if err != nil {
		return "", fmt.Errorf("JWT 파싱 실패: %w", err)
	}

	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		return "", fmt.Errorf("JWT claims를 읽을 수 없음")
	}

	sub, ok := claims["sub"].(string)
	if !ok {
		return "", fmt.Errorf("JWT 'sub' 클레임이 없거나 문자열이 아님")
	}
	return sub, nil
}

// Kratos Admin API를 호출하여 Identity 정보를 가져오는 함수
func getIdentityFromKratos(kratosID string) (*KratosIdentity, error) {
	req, err := http.NewRequest("GET", kratosAdminURL+"/identities/"+kratosID, nil)
	if err != nil {
		return nil, fmt.Errorf("Kratos 요청 생성 실패: %w", err)
	}
	// Kratos Admin API가 API Key나 다른 인증을 요구한다면 여기에 헤더를 추가해야 합니다.
	// 예: req.Header.Add("Authorization", "Bearer <your_kratos_api_key>")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("Kratos 요청 실패: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("Kratos Identity 조회 실패 - 상태 코드: %d, 응답: %s", resp.StatusCode, string(body))
	}

	var identity KratosIdentity
	if err := json.Unmarshal(body, &identity); err != nil {
		return nil, fmt.Errorf("Kratos Identity 응답 파싱 실패: %w", err)
	}
	return &identity, nil
}

func homeHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, err := r.Cookie("session_id")
	var htmlContent string
	if err != nil {
		htmlContent = `<h1>ORY 연동 Go 애플리케이션</h1><p><a href="/login">로그인 시작하기</a></p>`
	} else {
		htmlContent = `<h1>ORY 연동 Go 애플리케이션</h1><p>로그인 된 상태입니다.</p><p><a href="/profile">프로필 보기</a></p><p><a href="/logout">로그아웃</a></p>`
	}
	fmt.Fprint(w, generatePage("홈", htmlContent))
}

func loginHandler(w http.ResponseWriter, r *http.Request) {
	authURL, _ := url.Parse(hydraPublicURL + "/oauth2/auth")
	params := url.Values{}
	params.Add("client_id", hydraClientID)
	params.Add("redirect_uri", hydraRedirectURI)
	params.Add("response_type", "code")
	params.Add("scope", "openid profile offline_access")
	params.Add("state", "a-random-state-string-for-csrf-protection")
	authURL.RawQuery = params.Encode()
	http.Redirect(w, r, authURL.String(), http.StatusTemporaryRedirect)
}

func profileHandler(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie("session_id")
	if err != nil {
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}
	sessionMutex.RLock()
	session, ok := sessionStore[cookie.Value]
	sessionMutex.RUnlock()
	if !ok {
		http.Redirect(w, r, "/", http.StatusFound)
		return
	}
	var welcomeMessage string
	if session.Role == "admin" {
		welcomeMessage = "Hello World!"
	} else if session.Role == "user" {
		welcomeMessage = "당신은 user입니다."
	} else {
		welcomeMessage = "알 수 없는 역할의 사용자입니다."
	}
	finalMessage := fmt.Sprintf("<h1>%s</h1><p>로그인된 이메일: %s</p>", welcomeMessage, session.Email)
	fmt.Fprint(w, generatePage("프로필", finalMessage))
}

func logoutHandler(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie("session_id")
	if err == nil {
		sessionMutex.Lock()
		delete(sessionStore, cookie.Value)
		sessionMutex.Unlock()
		http.SetCookie(w, &http.Cookie{Name: "session_id", Value: "", Path: "/", MaxAge: -1})
	}
	logoutURL := kratosPublicURL + "/self-service/logout/browser"
	http.Redirect(w, r, logoutURL, http.StatusTemporaryRedirect)
}

func createNewSession(role, email string) (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	sessionID := base64.URLEncoding.EncodeToString(b)
	sessionMutex.Lock()
	sessionStore[sessionID] = Session{Role: role, Email: email}
	sessionMutex.Unlock()
    log.Printf("INFO: 사용자 '%s' 로그인 성공, 역할(role): '%s'", email, role)
	return sessionID, nil
}

func exchangeCodeForToken(code string) (*TokenResponse, error) {
	data := url.Values{}
	data.Set("grant_type", "authorization_code")
	data.Set("code", code)
	data.Set("redirect_uri", hydraRedirectURI)
	req, err := http.NewRequest("POST", hydraPublicURL+"/oauth2/token", strings.NewReader(data.Encode()))
	if err != nil { return nil, err }
	req.Header.Add("Content-Type", "application/x-www-form-urlencoded")
	req.SetBasicAuth(hydraClientID, hydraClientSecret)
	resp, err := http.DefaultClient.Do(req)
	if err != nil { return nil, err }
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK { return nil, fmt.Errorf("토큰 발급 실패: %s", string(body)) }
	var tokenResp TokenResponse
	err = json.Unmarshal(body, &tokenResp)
	return &tokenResp, err
}

func generatePage(title, body string) string {
	return fmt.Sprintf(`<!DOCTYPE html><html><head><title>%s</title><style>body { font-family: sans-serif; text-align: center; margin-top: 5rem; } h1 { color: #333; } p { margin-top: 1rem; } a { color: #007bff; }</style></head><body>%s</body></html>`, title, body)
}