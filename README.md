# GemDori

게임 엔진 없이 **Flutter 로 직접 만든 캐주얼 게임 모음**. 첫 게임은 **벽돌깨기(Brick Breaker)**.

> ▶ 플레이 링크 — GitHub Pages 배포 후 추가

## 특징

- **엔진 없이 순수 구현** — 게임 루프 · 충돌 판정 · 렌더링을 직접 작성 (Flame 등 미사용)
- **상태 계산과 그리기 분리** — 게임 상태는 화면·소리·입력을 모르는 순수 클래스. 테스트 195건
- **시간(dt) 기반 루프** — 기기 성능과 무관하게 같은 속도. 탭 전환 등으로 튀는 프레임은 1/30초로 상한
- **화면 크기가 난이도를 바꾸지 않게** — 경기장 비율 2:3 고정, 패들·공 크기와 속도를 경기장 폭에 비례
- **개발자 패널** — 넓은 화면에서 상태 · 사건 로그 · 치트를 표시. 릴리스 빌드에서는 코드째 빠짐

## 벽돌깨기

| 항목 | 내용 |
|---|---|
| 스테이지 | 11개 — 뒤로 갈수록 공 속도 상승 |
| 벽돌 | 내구도 1~3 (파랑 · 노랑 · 빨강) |
| 아이템 | 10종 — 도움(무적공 · 멀티공 · 감속 · 패들 확대) / 방해(벽돌 생성 3종 · 좌우 반전 · 패들 축소 · 가속) |
| 그 외 | 일시정지 · 효과음과 음소거 · 최고 점수(기기 저장) |

## 실행

개발 환경 Flutter 3.38.9 · 실행은 크롬 또는 엣지 (웹)

```powershell
flutter pub get
flutter test
.\run.ps1              # 빌드 시각을 넣어 크롬으로 실행 (Windows)
.\run.ps1 --profile    # 속도·버벅임 확인은 profile 로
```

- Windows 외 환경은 `flutter run -d chrome`

## 구조

```
lib/
  main.dart
  app/                  공통 — 홈(게임 목록) · 로딩 막 · 최고 점수 · 개발 모드 스위치
  games/brick/
    brick_state.dart    상태·계산 (순수 · 테스트 대상)
    brick_painter.dart  그리기
    brick_game_screen.dart  게임 루프 + 입력
    item.dart · ball.dart · brick.dart · sound.dart
    dev_panel.dart      개발자 패널 (릴리스 빌드 제외)
test/                   상태 · 아이템 · 최고 점수 · 패널 테스트
```

## 사용 기술

Flutter · Dart · `audioplayers` · `shared_preferences`
