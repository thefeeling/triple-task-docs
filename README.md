# 트리플여행자 클럽 마일리지 서비스

## 데이터베이스
![database](./database.png)
- MySQL 5.7 기준
- **[참고] 포인트를 제외한 테이블에 대해서는 최소한의 컬럼으로 설계 진행**
- 포인트 증감에 대한 이력 관리(`points`)
  - 지급/차감/사용/만료에 대한 모든 이력을 보관
  - 차감/사용/만료의 경우 음수 값 사용
- 리뷰로 인한 포인트 발생 이력도 추적이 가능해야 하므로, 별도의 테이블(`review_points`)로 이를 추적
- 포인트 지급 정책 관리(`point_policies`)
  - 정책 유효기간(시작일자, 종료일자)를 통하여 추후 정책 변경 및 추가에 대응
  - 사용 유무 컬럼을 별도로 지정하여 일시적으로 지급을 막을 수 있는 가능성도 고려
- [스미카_링크](./schema.sql)


## 포인트 적립 API Sequence
- 포인트 적립 API 호출에서 발생하는 흐름에 대하여 기술
  - 리뷰 작성/수정/삭제에 따른 Flow 분기
  - 포인트에 대한 이력 데이터 Insert(포인트 적립/수정/삭제)
  - 리뷰로 지급 받은 포인트 대한 이력 추적을 위한 히스토리 성격의 데이터 Insert
- 처리 시 발생하는 예외 케이스에 대해서는 HTTP STATUS 4XX/5XX를 반환

```puml
skinparam ParticipantPadding 20
skinparam BoxPadding 10
skinparam classFontName Courier


box SERVICE_API
	actor User
	participant ServiceAPI

	User -> ServiceAPI : HTTP/1.1 POST /v1/reviews
	ServiceAPI --> User : HTTP/1.1 200 OK
end box

box EVENT_API
	participant EventController
	participant UserService
	participant PointService
	database UserRepository
	database ReviewRepository
	database AttachmentRepository
	database PointRepository
	database ReviewPointRepository
	database UserPointRepository
	database PointPolicyRepository

	== 포인트 적립(리뷰 작성/수정/삭제 공통 로직) ==
	ServiceAPI -> ServiceAPI: 리뷰 작성/수정/삭제 \n응답 이후에 이벤트 처리
	
	ServiceAPI -> EventController: HTTP/1.1 POST /v1/events
	activate EventController
	EventController -> EventController: Validate RequestBody\n - 요청 본문의 데이터 타입 및 필수 값 체크
	EventController -> UserService: validateUser(id: UUID)\n - 별도 인증 Flow가 존재 할 경우 데이터베이스를 조회하지 않을 수 있음.
	activate UserService
	UserService -> UserRepository: userRepository.countById(id: UUID): Long
	alt 존재하지 않은 유저일 경우
		UserService --> ServiceAPI: HTTP/1.1 400 BadRequest
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		UserService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end
	deactivate UserService


	== 리뷰 작성에 따른 포인트 적립 ==
	EventController -> PointService: processPoints()
	activate PointService

	PointService <-> PointPolicyRepository: 포인트 지급 정책 조회\n - reviewPolicyRepository.findByType(type: ReviewPolicyType): List<ReviewPolicy>\n - 정책 테이블에 존재하는 지급 금액을 기준으로 포인트 지급 진행
	alt 지급 정책 데이터가 존재하지 않을 경우
		PointService --> ServiceAPI: HTTP/1.1 400 BadRequest
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		PointService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end

	PointService <-> ReviewRepository: 장소별 회원 리뷰 조회\n - reviewRepository.countByPlaceIdAndUserId(placeId: UUID, userId: UUID) : Long
	alt 데이터가 존재하지 않을 경우
		PointService --> ServiceAPI: HTTP/1.1 404 Not Found
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		PointService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end	


	alt 리뷰 엔티티의 content 값이 존재 && 글에 대한 리뷰 정책이 존재하는 경우
		PointService -> PointService : Point() 엔티티 생성
	end
	alt 이미지 첨부 시 포인트 지급 정책이 있을 경우 && 요청 본문에 첨부 이미지(`attachedPhotos`)가 있을 경우\n&& 요청 본문의 이미지 ID(`attachedPhotos`)들과 조회한 엔티티의 이미지 ID(`attachedPhotos`)가 동일 했을 경우
		PointService <-> AttachmentRepository: 첨부 이미지 존재 유무 체크\n - attachmentRepository.countByIds(ids: List<UUID>) : Long
		alt 첨부 이미지가 정상적으로 DB에 저정되어 있을 경우
			PointService -> PointService : Point() 엔티티 생성
		end
	end

	alt 장소별 최초 지급 정책이 존재하는 경우
		PointService <-> ReviewRepository: 장소별 최초 작성 유무 체크\n - reviewRepository.findTopOne(placeId: UUID) : Review\n - placeId를 기준, 리뷰 작성일 역순 정렬로 테이블의 Top 1의 엔티티를 조회
		alt 조회한 엔티티의 userId와 요청 본문의 userId가 같을 경우
			PointService -> PointService : Point() 엔티티 생성
		end		
	end


	PointService <-> PointRepository: Point 이력 데이터 save \n -pointRepository.saveAll(points: List<Point>)
	
	PointService <-> ReviewPointRepository: 리뷰 포인트 이력 데이터 Insert\n - reviewPointRepository.insert(ReviewPoint)\n - 리뷰 작성에 따른 구체적인 지급 내역을 컬럼에 JSON Serialize 한 후 반영\n - serialize하는 데이터에 point를 참조 할 수 있는 ID 데이터를 포함한다.
	
	PointService <-> PointRepository: Point 집계 데이터 조회\n - pointRepository.getAmountSumByUserId(userId: UUID): Long


	PointService <-> UserPointRepository: 회원 포인트 데이터 업데이트\n - userPointRepository.save(entity: UserPoint): UserPoint
	deactivate PointService
	PointService --> EventController: 집계된 회원 포인트 데이터 반환
	EventController --> ServiceAPI: HTTP/1.1 200 OK
	deactivate ServiceAPI

	ServiceAPI -> ServiceAPI: 집계된 회원 포인트 데이터 캐시 처리\n - setUserPointCache(userId: UUID)



	== 리뷰 수정에 따른 포인트 변경 ==
	
	EventController -> PointService: processPoints()
	activate PointService

	PointService <-> ReviewRepository: 장소별 회원 리뷰 조회\n - reviewRepository.findOneByPlaceIdAndUserId(placeId: UUID, userId: UUID) : Long
	alt 데이터가 존재하지 않을 경우
		PointService --> ServiceAPI: HTTP/1.1 404 Not Found
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		PointService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end

	PointService <-> UserPointRepository: 리뷰를 통하여 지급 받은 잔여 포인트 존재 유무 조회\n - userPointRepository.getAvailableReviewPoint(userId: UUID): Long	

	PointService <-> PointPolicyRepository: 리뷰 이미지 첨부 포인트 지급 정책 조회\n - reviewPolicyRepository.findByType(type: ReviewPolicyType): List<ReviewPolicy>\n - 정책 테이블에 존재하는 지급 금액을 기준으로 포인트 지급/차감 진행
	alt 지급 정책 데이터가 존재하지 않을 경우
		PointService --> ServiceAPI: HTTP/1.1 400 BadRequest
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		PointService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end

	PointService <-> ReviewPointRepository: 리뷰 포인트 이력 데이터 조회\n - reviewPointRepository.findOneByReviewIdOrderByCreateAtDesc(reviewId: UUID): ReviewPoint\n - 구체적인 지급 내역을 JSON deserialize

	alt 첨부 이미지 추가에 따른 포인트 지급 정책 존재 
		alt 글만 작성하여 포인트를 지급 받았을 경우 &&\n요청 본문에 이미지 첨부ID가 포함되어 있음

			PointService <-> AttachmentRepository: 첨부 이미지 존재 유무 체크\n - attachmentRepository.countByIds(ids: List<UUID>) : Long
			
				alt 참부 이미지가 존재하는 경우
					PointService <-> PointService: Point() 엔티티 생성\n- 이미지 첨부 포인트 지급 이력 추가			
				end
		else 요청 본문에 이미지 첨부 ID가 없으며 && 글과 이미지 첨부를 통하여 포인트를 지급 받았을 경우
			alt 차감 가능한 금액이 존재하는 경우
				PointService <-> PointService: Point() 엔티티 생성\n- 이미지 첨부 포인트 차감 이력 추가
			end
		end 
	end

	PointService <-> PointRepository: Point 이력 데이터 save \n -pointRepository.saveAll(points: List<Point>)\n - 이미지 첨부가 빠져서 생기는 차감의 경우 최초 지급 내역의 PointId를 OriginalId에 저장하여 이력 보관
	
	PointService <-> ReviewPointRepository: 리뷰 포인트 이력 데이터 Insert\n - reviewPointRepository.insert(ReviewPoint)\n - 리뷰 수정에 따른 구체적인 지급/차감 내역을 컬럼에 JSON Serialize 한 후 반영, point 엔티티의 ID 값을 포함해야 한다.
	
	PointService <-> PointRepository: Point 집계 데이터 조회\n - pointRepository.getAmountSumByUserId(userId: UUID): Long

	PointService <-> UserPointRepository: 회원 포인트 데이터 업데이트\n - userPointRepository.save(entity: UserPoint): UserPoint

	PointService --> EventController: 집계된 회원 포인트 데이터 반환
	EventController --> ServiceAPI: HTTP/1.1 200 OK
	deactivate PointService

	ServiceAPI -> ServiceAPI: 집계된 회원 포인트 데이터 캐시 처리\n - setUserPointCache(userId: UUID)


	== 리뷰 삭제에 따른 포인트 변경 ==
	EventController -> PointService: processPoints()
	activate PointService

	PointService <-> UserPointRepository: 리뷰를 통하여 지급 받은 잔여 포인트 존재 유무 조회\n - userPointRepository.getAvailableReviewPoint(userId: UUID): Long
	alt 잔여 포인트가 존재하지 않을 경우
		PointService --> ServiceAPI: HTTP/1.1 400 BadRequest
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		PointService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end	

	PointService <-> ReviewRepository: 장소별 회원 리뷰 조회\n - reviewRepository.countByPlaceIdAndUserId(placeId: UUID, userId: UUID) : Long
	alt 데이터가 존재하지 않을 경우
		PointService --> ServiceAPI: HTTP/1.1 404 Not Found
	else 데이터베이스 조회 중 에러가 발생 했을 경우
		PointService --> ServiceAPI: HTTP/1.1 500 ServiceUnavailable
	end

	PointService <-> ReviewPointRepository: 리뷰 포인트 이력 데이터 조회\n - reviewPointRepository.findOneByReviewIdOrderByCreateAtDesc(reviewId: UUID): ReviewPoint\n - 구체적인 지급 내역을 JSON deserialize

	PointService <-> PointService: Point() 엔티티 생성\n- 글 작성 포인트 차감 이력 추가
	alt 리뷰 포인트 지급 이력에 이미지 첨부 이력이 포함 되어 있을 경우
		PointService <-> PointService: Point() 엔티티 생성\n- 이미지 첨부 포인트 차감 이력 추가
	end

	alt 리뷰 포인트 지급 이력에 장소별 최초 리뷰 작성 이력이 포함 되어 있을 경우
		PointService <-> PointService: Point() 엔티티 생성\n- 장소별 최초 리뷰 작성 포인트 차감 이력 추가
	end

	PointService <-> PointRepository: Point 이력 데이터 save \n -pointRepository.saveAll(points: List<Point>)\n - 최초 지급 내역의 PointId를 OriginalId에 저장하여 이력 보관\n - 리뷰 삭제에 따른 차감 이력 추가
	
	PointService <-> ReviewPointRepository: 리뷰 포인트 이력 데이터 Insert\n - reviewPointRepository.insert(ReviewPoint)\n - 구체적인 차감 이력을 컬럼에 JSON Serialize 한 후 반영
	
	PointService <-> PointRepository: Point 집계 데이터 조회\n - pointRepository.getAmountSumByUserId(userId: UUID): Long

	PointService <-> UserPointRepository: 회원 포인트 데이터 업데이트\n - userPointRepository.save(entity: UserPoint): UserPoint

	PointService --> EventController: 집계된 회원 포인트 데이터 반환
	EventController --> ServiceAPI: HTTP/1.1 200 OK
	deactivate PointService

	ServiceAPI -> ServiceAPI: 집계된 회원 포인트 데이터 캐시 처리\n - setUserPointCache(userId: UUID)
end box
```

## 포인트 조회 API Sequence
- 포인트 조회 API 호출에서 발생하는 흐름에 대하여 기술
	- 포인트 적립 API 호출의 응답 값을 기준으로 캐시 데이터 활용
	- 캐시 데이터 만료의 경우, 포인트 조회 API 호출 후 캐시 처리
- 처리 시 발생하는 예외 케이스에 대해서는 HTTP STATUS 4XX/5XX를 반환
```puml
skinparam ParticipantPadding 20
skinparam BoxPadding 10
skinparam classFontName Courier

box SERVICE_API
	actor User
	participant ServiceAPI

	User -> ServiceAPI : HTTP/1.1 GET /v1/users/{userId}/total-point
	ServiceAPI -> ServiceAPI: 집계된 회원 포인트 데이터 캐시 존재 유무 확인\n - getUserPointCache(userId: UUID)

	
end box

box EVENT_API
	participant UserPointController
	participant UserService
	participant UserPointService
	database UserRepository
	database UserPointRepository
	
	alt userId에 해당하는 캐시 정보가 존재하지 않을 경우
		ServiceAPI -> UserPointController: HTTP/1.1 GET /v1/users/{userId}/total-point

		alt 인증 Flow(TOKEN 혹은 Session)가 없을 경우
			UserPointController -> UserService: 존재하는 유저 유무 체크\n- existUser(userId: UUID): Boolean
			UserService <-> UserPointRepository: 유저 조회\n- userRepository.countById(userId: UUID): Long
			UserService -> UserPointController: 존재 유무 반환
		end

		UserPointController -> UserPointService: 유저 포인트 조회 서비스 호출\n - getUserPoint(userId: UUID): UserPoint
		UserPointService <-> UserPointRepository: 유저 포인트 조회\n - userPointRepository.findByUserId(userId: UUId): UserPoint
		UserPointService -> UserPointController: 포인트 엔티티 반환
		UserPointController -> ServiceAPI: HTTP/1.1 200 OK

		ServiceAPI -> ServiceAPI: 회원 포인트 데이터 캐시 처리\n - setUserPointCache(userId: UUID)
	end



	ServiceAPI --> User : HTTP/1.1 200 OK

end box
```
