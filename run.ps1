# 빌드 시각을 넣어 크롬으로 띄운다.
#   화면(개발자 패널 맨 아래)에 그 시각이 보이므로,
#   지금 보고 있는 것이 방금 고친 코드인지 눈으로 확인할 수 있다.
# 뒤에 붙인 인자는 그대로 flutter run 에 넘긴다 (2026-09-11) — 예) .\run.ps1 --profile
#   버벅임·속도를 볼 때는 --profile. 기본(디버그)은 최적화 전 코드라 느린 게 정상이다
$at = Get-Date -Format 'MM-dd HH:mm:ss'
Write-Host "BUILD_AT = $at"
flutter run -d chrome --dart-define=BUILD_AT=$at @args
