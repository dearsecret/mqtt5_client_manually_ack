# mqtt5_client_custom

본 프로젝트는 [mqtt5_client](https://github.com/shamblett/mqtt5_client) 라이브러리를 기반으로, 모바일 환경에 최적화된 안정성 기능을 추가한 커스텀 버전입니다.

## 주요 개선 기능

### 1. 지능형 재연결 (Exponential Backoff)

네트워크 불안정 시 서버 부하를 방지하고 재연결 성공률을 높이기 위해 **지수 백오프 전략**이 도입되었습니다. `onAutoReconnect` 콜백에서 비동기 작업을 지원하여, 재연결 시도 간격을 기하급수적으로 늘릴 수 있습니다.

### 2. 수동 ACK 모드 (Manual Acknowledgement)

기존의 자동 `PUBACK` 반환 대신, 비즈니스 로직 처리가 완료된 후 개발자가 직접 `PUBACK`를 제어할 수 있습니다.

## 사용법

### Manually PUBACK

```dart
client.manuallyAcknowledgeQos1 = true;
```

### 재연결 정책 설정 (지수 백오프)

`onAutoReconnect` 콜백을 `async`로 설정하여 재연결 간격을 제어합니다.

```dart
int _retryCount = 0;

client.autoReconnect = true;
client.onAutoReconnect = () async {
  final int delay = pow(2, min(_retryCount, 5)).toInt();
  print('${delay}초 후 재연결 시도...');
  await Future.delayed(Duration(seconds: delay));
  _retryCount++;
};

client.onAutoReconnected = () {
  _retryCount = 0; // 성공 시 초기화
};
```
