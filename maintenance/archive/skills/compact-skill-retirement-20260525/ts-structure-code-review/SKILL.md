---
name: ts-structure-code-review
description: Use for TypeScript structure/code review, TS PR review, architecture boundary review, type-contract drift, error-handling review, duplication/shape drift review, and test abstraction review. Do not use for style-only formatting reviews.
---

# TypeScript 구조/코드 리뷰 체크리스트

## 목적

TypeScript 코드베이스를 리뷰할 때 단순 스타일, 길이, 취향 문제가 아니라 **구조적 결함, 타입 계약 불안정성, 실패 처리 누락, shape drift, 테스트 결합도**를 찾는다.

리뷰 결과는 반드시 다음 세 가지로 정리한다.

1. 무엇이 문제인가?
2. 왜 문제인가?
3. 어디를 먼저 고치면 되는가?

코드 수정을 명시적으로 요청받지 않았다면 리뷰만 수행한다. 수정안을 제시할 수는 있지만 임의로 파일을 변경하지 않는다.

## 사용 시점

다음 요청에 이 스킬을 사용한다.

- TypeScript / JavaScript / Node.js / React / Next.js 코드 리뷰
- PR 리뷰, 구조 리뷰, 아키텍처 경계 점검
- 타입, schema, validator, API 응답, UI 모델 간 drift 점검
- 에러 처리, fallback, cleanup, async 실패 흐름 점검
- 중복 로직, helper zoo, barrel import, util 남용 점검
- 테스트가 계약을 검증하는지, 구현 세부사항에 결합되어 있는지 점검

다음 경우에는 이 스킬을 주된 기준으로 쓰지 않는다.

- 단순 포맷팅, 네이밍만 보는 리뷰
- 알고리즘 정답성만 보는 리뷰
- 보안 감사, 성능 프로파일링, 접근성 감사처럼 별도 전문 체크리스트가 필요한 작업
- 사용자가 명시적으로 다른 리뷰 기준을 지정한 작업

## 리뷰 원칙

- 큰 축부터 본다. 권장 순서는 `C 구조 경계 → D 타입/계약 → E 실패 처리 → A 크기/단순성 → B 중복/Shape → F 추상화/테스트`이다.
- 크기 자체보다 경계 붕괴를 먼저 의심한다. 긴 함수는 보통 검증, 정규화, 상태 변경, I/O, 에러 처리가 한곳에 섞인 증상이다.
- 문제를 반드시 **증상**과 **구조적 원인**으로 나눠 적는다.
- 지적은 실행 가능해야 한다. “분리 필요”처럼 모호하게 끝내지 말고, 어떤 책임을 어디로 이동할지 제안한다.
- 모든 항목을 기계적으로 나열하지 않는다. 실제 코드에서 근거가 있는 항목만 주요 발견사항으로 올린다.
- 파일 경로와 라인 번호를 확인할 수 있으면 반드시 포함한다.
- 불확실한 추정은 `추정`, `확인 필요`로 표시한다.
- 기존 설계 의도, 프레임워크 제약, 팀 컨벤션을 확인하지 못한 경우 단정하지 않는다.
- 변경 반경 대비 효과가 큰 지점을 우선한다.

## 사전 확인

리뷰 전에 가능한 범위에서 다음을 확인한다.

- 대상 파일, PR diff, 변경 목적, 주요 진입점
- `package.json` scripts
- `tsconfig.json`의 strict 관련 설정
- ESLint, import rule, boundary rule, build rule
- framework/runtime: Node.js, React, Next.js, NestJS 등
- schema/validator 사용 여부: Zod, Valibot, Yup, io-ts, class-validator 등
- 테스트 도구: Vitest, Jest, Playwright, Testing Library 등
- API/DB/외부 I/O 경계

명령 실행이 가능하고 프로젝트에 스크립트가 이미 정의되어 있으면 다음을 우선한다.

- 타입 체크: `npm run typecheck`, `pnpm typecheck`, `yarn typecheck`, 또는 `tsc --noEmit`
- 린트: `npm run lint`, `pnpm lint`, `yarn lint`
- 관련 테스트: 변경 파일과 직접 관련된 테스트만 우선 실행

의존성 설치, 마이그레이션, destructive command, 전체 리팩터링은 사용자가 요청하지 않으면 수행하지 않는다.

## 출력 형식

리뷰 결과는 아래 구조를 기본으로 한다.

```md
## 결론

전체 구조상 가장 큰 위험은 ... 입니다. 먼저 고칠 지점은 ... 입니다.

## 우선순위 발견사항

### 1. [P1] 제목

- 증상: ...
- 구조적 원인: ...
- 영향: ...
- 먼저 고칠 지점: ...
- 근거: `path/to/file.ts:10-42`

### 2. [P2] 제목

- 증상: ...
- 구조적 원인: ...
- 영향: ...
- 먼저 고칠 지점: ...
- 근거: `path/to/file.ts:80-120`

## 빠른 판정

- 지금 당장 손댈 1순위: ...
- 전체 구조를 망가뜨리는 중심 병목: ...
- 수정 반경 대비 효과가 가장 큰 지점: ...
- 요구사항이 바뀌면 먼저 깨질 모듈: ...
- 지금 삭제하면 위험한 후보: ...

## 체크리스트 결과

- C 구조 경계: 통과 / 주의 / 위험 / 확인 불가
- D 타입/계약: 통과 / 주의 / 위험 / 확인 불가
- E 실패 처리: 통과 / 주의 / 위험 / 확인 불가
- A 크기/단순성: 통과 / 주의 / 위험 / 확인 불가
- B 중복/Shape: 통과 / 주의 / 위험 / 확인 불가
- F 추상화/테스트: 통과 / 주의 / 위험 / 확인 불가

## 권장 수정 순서

1. ...
2. ...
3. ...

## 검증 방법

- ...
```

## 심각도 기준

- `P0`: 즉시 수정 필요. 데이터 손실, 보안 문제, 런타임 크래시, 배포 차단 가능성이 높다.
- `P1`: 구조적 병목. 이후 변경 비용을 지속적으로 키우거나 여러 모듈을 깨뜨릴 가능성이 높다.
- `P2`: 중간 위험. 현재는 작동하지만 확장, 테스트, 유지보수 비용을 키운다.
- `P3`: 정리 권장. 명확성, 일관성, 작은 중복 개선 수준이다.

확신도도 필요하면 `High / Medium / Low`로 표시한다.

---

# A. 크기와 단순성

## 점검 질문

- 크기와 복잡도는 현재 문제에 비해 적절한가?
- 한 함수나 파일이 여러 책임을 동시에 지고 있지는 않은가?
- `helper zoo`처럼 보조 함수가 무질서하게 증식해 책임이 흐려지지는 않았는가?
- 과분할, 불필요한 레이어링, 의미 없는 파일 쪼개기가 존재하지 않는가?
- 큰 코드가 단순히 “길다”의 문제가 아니라 검증, 정규화, 상태 변경, I/O, 에러 처리가 한곳에 섞인 결과는 아닌가?

## 판단 기준

위험 신호:

- 함수 하나가 입력 검증, 데이터 정규화, 도메인 판단, 저장, 이벤트 발행, 로깅, 에러 매핑을 모두 수행한다.
- 파일 수는 많지만 책임 기준이 아니라 타입별, 함수별, 취향별로 쪼개져 있다.
- helper가 도메인 의미 없이 `utils`, `helpers`, `common` 아래로 계속 증식한다.
- 함수 길이를 줄였지만 실제 상태 변경 경로와 오류 경로가 더 추적하기 어려워졌다.

개선 방향:

- 책임 단위로 분리한다. 예: `validate → normalize → decide → mutate → persist → report`.
- 단순 길이 축소가 아니라 변경 이유가 같은 코드를 같은 곳에 둔다.
- helper는 도메인 이름을 갖는 모듈이나 명확한 boundary 아래로 이동한다.
- 의미 없는 thin layer는 제거한다.

---

# B. 중복과 Shape 관리

## 점검 질문

- 중복 구현, 복붙, 유사 로직의 병렬 유지가 존재하는가?
- shared shape가 여러 곳에 흩어져 함께 썩는 구조는 아닌가?
- 타입, schema, validator, API 응답, UI 모델이 서로 drift하고 있지는 않은가?
- dead code, 더 이상 쓰이지 않는 우회 경로, 과거 마이그레이션 잔재가 남아 있지는 않은가?
- 동일한 멀티스텝 워크플로우나 파이프라인이 서로 다른 진입점에서 독립적으로 구현되고 있지는 않은가?

## TypeScript 특화 점검

- API DTO, DB entity, domain model, form state, view model이 같은 shape처럼 보이지만 각자 따로 선언되어 있지 않은가?
- runtime validator와 TypeScript type이 서로 다른 출처에서 관리되고 있지 않은가?
- `Partial<T>`, `Pick<T>`, `Omit<T>`가 의미 있는 상태 모델 대신 임시 shape 조합으로 남용되고 있지 않은가?
- mapper가 여러 곳에 흩어져 같은 변환을 조금씩 다르게 수행하지 않는가?

## 판단 기준

위험 신호:

- 필드명이 바뀌면 API, UI, validator, 테스트를 여러 곳에서 수동으로 같이 고쳐야 한다.
- 같은 normalize 로직이 hook, service, route handler, test fixture에 각각 있다.
- legacy path가 아직 import 가능하고 실제로 호출될 수 있다.
- “거의 같은” 타입이 많아졌지만 어떤 것이 canonical shape인지 불명확하다.

개선 방향:

- canonical shape를 하나 정하고 변환 경계를 명확히 한다.
- runtime schema에서 static type을 파생하거나, 최소한 schema/type drift를 테스트로 잡는다.
- 멀티스텝 파이프라인은 단일 orchestrator 또는 공유 workflow로 모은다.
- dead code는 호출 경로 확인 후 제거한다.

---

# C. 응집도와 구조 경계

## 점검 질문

- 모듈, 파일, 함수의 응집도는 충분히 높은가?
- 책임과 의존 방향이 자연스럽고 무리하지 않은가?
- 디커플링이 잘 이루어졌는가?
- 순환 의존성이 존재하지는 않는가?
- 검증, 정규화, 에러 처리 같은 교차 관심사가 여기저기 흩어지지 않고 적절한 병목 지점에서 관리되고 있는가?
- 상태 변경은 단일 진입점 또는 예측 가능한 경로를 통하는가?
- 여러 위치에서 상태가 암묵적으로 갱신되고 있지는 않은가?
- 모듈 경계가 lint, import rule, build rule 등으로 실제 강제되고 있는가?
- 파일이 위계와 의존도에 따라 정리되어 있는가?
- 배럴 파일이 import amplification을 일으키고 있지 않은가?
- `index.ts` 하나를 import했을 때 무관한 모듈까지 전이적으로 로드되지는 않는가?

## TypeScript 특화 점검

- feature 모듈이 다른 feature의 내부 구현을 직접 import하고 있지 않은가?
- domain layer가 UI, framework, DB client, request object에 의존하고 있지 않은가?
- server-only 코드가 client bundle로 새어 나갈 수 있지 않은가?
- `index.ts` 배럴이 side effect import나 무관한 re-export를 포함하고 있지 않은가?
- path alias가 의존 방향을 숨기고 있지 않은가?

## 판단 기준

위험 신호:

- 하위 모듈이 상위 모듈을 import한다.
- 한 feature 변경이 무관한 feature의 build/test 실패를 유발한다.
- 상태를 바꾸는 함수가 여러 파일에 흩어져 있고 호출 순서에 암묵적으로 의존한다.
- barrel import 하나로 전체 graph가 로드된다.
- import rule이 없어 “하지 말아야 할 import”를 코드 리뷰 기억에 의존한다.

개선 방향:

- public API와 internal API를 분리한다.
- import boundary를 ESLint rule, tsconfig path, package boundary, build rule로 강제한다.
- 상태 변경 진입점을 줄이고 command/service/orchestrator 단위로 모은다.
- barrel은 타입 전용 또는 좁은 public API에만 사용한다.
- 순환 의존은 shared contract 추출, dependency inversion, boundary 재설계 중 하나로 끊는다.

---

# D. 타입과 계약

## 점검 질문

- 타입 조임과 인터페이스 계약은 안정적인가?
- 인터페이스, 타입 가드, 제네릭은 필요한 만큼만 사용되고 있는가?
- 네이밍, 규칙, 표현 방식은 일관적인가?
- 암묵 계약, 숨겨진 import, 초기화 순서 의존성 같은 비가시적 결합이 존재하지 않는가?
- 상태에 따라 존재 여부가 달라지는 필드가 optional로 뭉뚱그려져 있지는 않은가?
- discriminated union으로 좁힐 수 있는 상태를 느슨한 optional 필드나 문자열로 처리하고 있지는 않은가?
- enum/union이어야 할 값이 stringly-typed로 방치되어 있지는 않은가?

## TypeScript 특화 점검

- `any`가 boundary 안쪽까지 전파되지 않는가?
- `unknown`을 받은 뒤 적절히 narrowing하고 있는가?
- type assertion `as Foo`가 검증 없이 계약 위반을 숨기고 있지 않은가?
- optional field가 실제로는 상태별 필수 필드인데 `?:`로 덮여 있지 않은가?
- boolean flag 조합이 불가능한 상태를 허용하고 있지 않은가?
- generic이 실제 제약을 표현하지 못하고 호출부 추론을 흐리게 하지 않는가?
- external input은 runtime validation을 거치는가?

## 판단 기준

위험 신호:

- `status: string`과 optional field 조합으로 상태를 표현한다.
- `type Foo = Partial<Original>`이 여러 layer에 퍼져 있다.
- `as SomeType`이 API 응답, localStorage, env, DB row 같은 외부 입력에 직접 적용된다.
- 존재하지 않아야 할 상태를 TypeScript가 허용한다.
- 초기화 순서를 지키지 않으면 런타임에서만 실패한다.

개선 방향:

- 상태 모델은 discriminated union으로 좁힌다.
- string literal union 또는 enum-like const object로 허용값을 제한한다.
- 외부 입력은 runtime schema로 검증하고 내부에서는 검증된 타입만 사용한다.
- 불가능한 상태를 타입으로 표현하지 못하면 타입 모델을 재설계한다.
- assertion은 경계에서만 제한적으로 사용하고 근거를 남긴다.

예시:

```ts
// 나쁨: 불가능한 상태를 허용한다.
type RequestState = {
  status: string;
  data?: User;
  error?: Error;
};

// 좋음: 상태별 필수 필드가 타입으로 강제된다.
type RequestState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: User }
  | { status: 'error'; error: Error };
```

---

# E. 실패 처리와 방어 전략

## 점검 질문

- 방어 코드는 필요한 경계에만 최소한으로 존재하는가?
- 호출부마다 중복 방어가 반복되고 있지는 않은가?
- `catch`는 에러를 삼키지 않고 적절히 전파, 기록, 표면화하고 있는가?
- fallback, graceful degradation, silent recovery가 버그 은닉 장치로 작동하고 있지는 않은가?
- `catch`가 에러의 실제 원인과 다른 코드나 메시지로 재분류하고 있지는 않은가?
- 예: 권한 오류를 “파일 없음”으로 보고하고 있지는 않은가?
- 리소스 정리 cleanup이 `finally` 또는 dispose 패턴으로 보장되는가?
- 비동기 흐름에서 에러가 삼켜지지 않는가?
- 예: fire-and-forget `Promise`, unhandled rejection

## TypeScript 특화 점검

- `catch (error)`의 `error`를 `any`처럼 다루지 않고 `unknown`으로 narrowing하는가?
- domain error, infrastructure error, validation error가 구분되는가?
- Promise를 반환해야 하는 곳에서 await 없이 누락하지 않는가?
- 이벤트 핸들러, queue, timer, subscription, stream에서 cleanup과 실패 보고가 보장되는가?
- retry/fallback이 원인 파악을 어렵게 만들지 않는가?

## 판단 기준

위험 신호:

- `catch {}` 또는 `catch (e) { return defaultValue; }`가 있다.
- fallback이 실제 데이터 손상이나 권한 실패를 정상 상태처럼 보이게 만든다.
- cleanup이 성공 경로에만 있고 실패 경로에는 없다.
- fire-and-forget Promise에 `.catch()`나 관찰 가능한 에러 경로가 없다.
- 에러 재분류가 실제 원인과 다르다.

개선 방향:

- 외부 경계에서만 defensive validation을 집중시킨다.
- 내부 호출부의 반복 방어는 제거하고 검증된 타입/계약을 전달한다.
- 에러는 원인을 보존하면서 domain-level error로 매핑한다.
- fallback은 사용자 경험용인지, 데이터 정합성용인지 목적을 명확히 한다.
- 비동기 side effect는 관찰 가능한 실패 경로를 둔다.

예시:

```ts
// 나쁨: 권한 오류와 파일 없음 오류를 구분하지 못한다.
try {
  return await readUserFile(path);
} catch {
  return null;
}

// 좋음: 원인을 보존하고 호출자가 판단할 수 있게 한다.
try {
  return await readUserFile(path);
} catch (error: unknown) {
  throw mapFileReadError(error, { path });
}
```

---

# F. 추상화와 테스트

## 점검 질문

- 추상화 수준은 적절한가?
- 과도하게 일반화되어 있거나, 반대로 반복을 견디지 못할 만큼 부족하지는 않은가?
- 테스트는 happy path뿐 아니라 엣지 케이스, 실패 케이스, 계약 위반 상황까지 포함하고 있는가?
- 테스트가 구현 세부사항이 아니라 동작/계약을 검증하고 있는가?
- 내부 리팩터링 시 테스트가 함께 깨진다면 테스트가 구현에 과하게 결합된 것은 아닌가?
- mock 경계가 적절한가?
- 너무 깊이 mock해서 테스트는 통과하지만 실제 통합은 실패하는 구조가 되지 않았는가?

## TypeScript 특화 점검

- 테스트 fixture가 실제 runtime schema와 drift하지 않는가?
- mock이 타입만 만족하고 실제 API 계약은 만족하지 않는 구조가 아닌가?
- private helper 호출 결과만 테스트하고 public behavior는 검증하지 않는가?
- 타입 테스트가 필요한 곳에 `tsd`, `expectTypeOf`, `@ts-expect-error` 같은 검증이 있는가?
- contract test 또는 integration test가 필요한 boundary를 unit mock으로만 대체하고 있지 않은가?

## 판단 기준

위험 신호:

- 추상화 이름이 넓지만 실제 구현은 특정 use case 하나에 묶여 있다.
- 내부 함수 이름, 호출 횟수, mock implementation 순서에 테스트가 과하게 의존한다.
- 외부 API, DB, queue, file system boundary를 모두 mock해서 통합 실패를 못 잡는다.
- 실패 케이스 테스트가 없고 happy path snapshot만 있다.

개선 방향:

- 추상화는 실제 반복 패턴이 2~3회 확인된 뒤 도입한다.
- 테스트는 public contract, observable behavior, state transition을 검증한다.
- mock은 시스템 외부 경계에서 멈춘다.
- 중요한 mapper/schema/API 계약은 contract test를 둔다.
- 리팩터링에도 깨지지 않는 테스트와, 계약 위반 시 반드시 깨지는 테스트를 구분한다.

---

# 빠른 판정용 보조 질문

리뷰 마지막에 다음 질문으로 우선순위를 압축한다.

- 지금 당장 손댈 1순위는 무엇인가?
- 전체 구조를 망가뜨리는 중심 병목은 무엇인가?
- 수정 반경 대비 효과가 가장 큰 지점은 어디인가?
- 지금 고치지 않으면 이후 모든 변경 비용을 키우는 부분은 무엇인가?
- 요구사항이 살짝 바뀌면 어떤 모듈이 먼저 깨지는가?
- 증상은 무엇이고, 구조적 원인은 무엇인가?
- 지금 삭제하면 위험한 후보는 무엇인가?

---

# 주요 안티패턴

## God object / mega interface

하나의 객체나 인터페이스가 지나치게 많은 책임과 필드를 가진다. 변경 이유가 여러 개라면 분리 후보이다.

## helper zoo

도메인 의미가 없는 helper가 무질서하게 증식한다. 호출부는 줄었지만 책임과 흐름은 더 흐려진다.

## hidden shared state

여러 모듈이 같은 상태를 암묵적으로 읽고 쓴다. 상태 변경 경로가 추적되지 않는다.

## catch 후 무시

에러를 기록, 전파, 표면화하지 않고 삼킨다. 실제 실패가 정상 흐름처럼 보인다.

## fallback으로 상태를 덮음

fallback이 사용자 경험 보완이 아니라 버그 은닉 장치로 작동한다.

## shared shape drift

타입, schema, validator, API 응답, UI 모델이 같은 shape를 각자 다르게 관리하며 서서히 어긋난다.

## 파일만 나뉘고 책임은 안 나뉜 과분할

파일 수는 많지만 변경 이유와 책임 경계가 분리되지 않는다.

## boundary 없는 util 남용

`utils`, `common`, `shared`가 모든 layer에서 접근 가능한 쓰레기통이 된다.

## temporal coupling

정해진 순서대로 호출해야 하지만 타입, API, 상태 모델이 그 순서를 강제하지 않는다.

## feature envy

한 모듈이 다른 모듈의 내부 자료구조나 세부 구현을 과도하게 참조한다.

## stringly-typed

enum 또는 union으로 제한해야 할 값을 임의 문자열로 처리한다.

## barrel bomb

배럴 하나를 import하면 re-export된 전체 모듈 그래프가 로드된다.

---

# 추천 사용법

## 1. 먼저 큰 축부터 본다

권장 순서:

1. C 구조 경계
2. D 타입/계약
3. E 실패 처리
4. A 크기/단순성
5. B 중복/Shape
6. F 추상화/테스트

크기보다 경계가 먼저 무너지기 쉽기 때문이다.

## 2. 문제를 증상과 원인으로 나눠 적는다

예시:

```md
증상: 함수가 길다.
원인: 검증, 정규화, 상태 변경, 에러 처리가 한곳에 섞여 있다.
먼저 고칠 지점: 입력 검증과 정규화를 boundary 함수로 분리하고, 상태 변경은 단일 command로 모은다.
```

## 3. 지적은 세 문장으로 마무리한다

각 발견사항은 최소한 아래 세 질문에 답해야 한다.

```md
무엇이 문제인가?
왜 문제인가?
어디를 먼저 고치면 되는가?
```

---

# 최종 리뷰 품질 기준

좋은 리뷰는 다음 조건을 만족한다.

- 단순히 “복잡하다”가 아니라 복잡성이 생긴 구조적 원인을 설명한다.
- 파일/라인 근거가 있다.
- 수정 우선순위가 있다.
- 작은 취향 문제가 아니라 변경 비용을 키우는 병목을 먼저 다룬다.
- TypeScript 타입 모델과 runtime 계약을 함께 본다.
- 실패 처리와 테스트까지 포함해 실제 운영 위험을 판단한다.
- 제안이 현재 코드베이스의 경계와 컨벤션을 깨지 않는다.

나쁜 리뷰는 다음 패턴을 가진다.

- 모든 체크리스트를 기계적으로 나열한다.
- “분리하세요”, “추상화하세요”, “타입을 강화하세요”처럼 실행 지점이 없다.
- 증상만 지적하고 원인을 말하지 않는다.
- 작은 스타일 문제를 P1처럼 다룬다.
- 코드베이스 근거 없이 일반론을 단정한다.
