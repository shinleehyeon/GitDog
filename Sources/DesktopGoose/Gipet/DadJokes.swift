// Local addition — 아재개그 lines the dog says (via a speech bubble) when it
// detects you've committed today (or via the "말풍선 💬" menu item). Kept short
// and pre-wrapped with "\n" so the bubble never grows past the character view.

import Foundation

enum DadJokes {
    static let lines: [String] = [
        "왕이 양쪽에\n있으면?\n우왕좌왕",
        "비 오는 날\n먹는 햄은?\n습햄",
        "몸에 안 좋은\n청바지는?\n유해진",
        "바람이 귀엽게\n부는 곳은?\n분당",
        "부엉이가 물에\n빠지면?\n첨부엉 첨부엉",
        "빵이 목장에\n간 이유는?\n소보로",
        "동생 편만 드는\n세상은?\n형 편 없는 세상",
        "3월에 대학생을\n못 이기는\n이유는?\n개강하니까",
        "9가\n자기소개하면?\n전구",
        "가장 인기 있는\n벌레는?\n스타벅스",
        "가장 폭력적인\n동물은?\n팬다",
        "감기에 또\n걸리면?\n되감기",
        "거북이가\n소화제를 먹은\n이유는?\n속이 거북해서",
        "고등학생들이\n싫어하는\n나무는?\n야자나무",
        "고추장보다\n높은 사람은?\n초고추장",
        "과자가\n자기소개하면?\n전과자",
        "귤이 감을 보고\n한 말은?\n유감",
        "딸기가 직장을\n잃으면?\n딸기시럽",
        "모든 사람을\n일어나게 하는\n숫자는?\n다섯",
        "비가 1시간\n동안 내리면?\n추적 60분",
        "콩 한 알을\n영어로 하면?\n원빈",
        "햄버거의\n색깔은?\n버건디",
        "있을 수도 없을\n수도 있는 섬은?\n아마도",
        "미소의\n반대말은?\n당기소",
        "물고기가\n싫어하는 물은?\n그물",
        "미국에 비가\n내리면?\nUSB",
        "서울에 사는\n거지 이름은?\n설거지",
        "왕이 담배를\n피우면?\n스모킹",
        "커플이\n좋아하는\n곤충은?\n잠자리",
        "유부남이 제일\n무서워하는\n치킨은?\n마눌치킨",
        "공이 웃으면?\n풋볼",
        "왕이 넘어질 때\n나는 소리는?\n킹콩",
        "송혜교 송강\n송윤아의\n공통점은?\n성동일",
        "혀가 거짓말할\n때 하는 말은?\n전 혀 아닙니다",
        "자기만 옳다고\n하는 사람이\n사는 집은?\n고집",
        "덜 뚱뚱한\n사람들이 사는\n동네는?\n반포동",
        "사람이 죽지\n않는 산맥은?\n안데스산맥",
        "입이\n평화로우면?\n마우스피스",
        "이탈리아의\n날씨는?\n습하게띠",
        "신동 옆에 있는\n사람은?\n신동엽",
        "떡집 사장이\n주식을 안 하는\n이유는?\n떡상할까봐",
        "닭에게 작은\n옷을 입히면?\n꼭끼오",
        "세상에서 가장\n착한 사자는?\n자원봉사자",
        "맥주가 죽기 전\n한 말은?\n유언비어",
        "한의사가\n카지노에서\n하는 말은?\n인생은 한 방",
        "개가 벽 보고\n한 말은?\n월월",
        "전화로 세운\n건물은?\n콜로세움",
        "왕이 궁에 가기\n싫을 때 하는\n말은?\n궁시렁궁시렁",
        "직접 만든\n총은?\n손수건",
        "뚱뚱한 사람들이\n모인 곳은?\n개포동",
        // Commit-themed bonus lines.
        "커밋 완료!\n오늘도 잔디\n심었네 🌱",
        "푸시까지 했어?\n역시 너야 너 🚀",
    ]

    /// A random joke. `avoid` lets the caller skip the previous one so the same
    /// joke doesn't show twice in a row.
    static func random(avoiding avoid: String? = nil) -> String {
        let pool = lines.count > 1 ? lines.filter { $0 != avoid } : lines
        let source = pool.isEmpty ? lines : pool
        return source[Int.random(in: 0..<source.count)]
    }
}
