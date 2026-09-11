# 빌드 시각을 넣어 크롬으로 띄운다.
#   화면(개발자 패널 맨 아래)에 그 시각이 보이므로,
#   지금 보고 있는 것이 방금 고친 코드인지 눈으로 확인할 수 있다.
$at = Get-Date -Format 'MM-dd HH:mm:ss'
Write-Host "BUILD_AT = $at"
flutter run -d chrome --dart-define=BUILD_AT=$at
