import Foundation

nonisolated struct TxtTocRule: Sendable {
    let id: Int
    let enable: Bool
    let name: String
    let rule: String
    let serialNumber: Int

    static let defaults: [TxtTocRule] = [
        TxtTocRule(
            id: -2,
            enable: true,
            name: "目录",
            rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$"#,
            serialNumber: 0
        ),
        TxtTocRule(
            id: -1,
            enable: true,
            name: "目录(去空白)",
            rule: #"(?<=[　\s])(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和]))).{0,30}$"#,
            serialNumber: 1
        ),
        TxtTocRule(
            id: -3,
            enable: false,
            name: "目录(匹配简介)",
            rule: #"(?<=[　\s])(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$"#,
            serialNumber: 2
        ),
        TxtTocRule(
            id: -4,
            enable: false,
            name: "目录(古典、轻小说备用)",
            rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|回(?![合来事去])|场(?![和合比电是])|话|篇(?!张))).{0,30}$"#,
            serialNumber: 3
        ),
        TxtTocRule(
            id: -5,
            enable: false,
            name: "数字(纯数字标题)",
            rule: #"(?<=[　\s])\d+\.?[ 　\t]{0,4}$"#,
            serialNumber: 4
        ),
        TxtTocRule(
            id: -6,
            enable: false,
            name: "大写数字(纯数字标题)",
            rule: #"(?<=[　\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,12}[ 　\t]{0,4}$"#,
            serialNumber: 5
        ),
        TxtTocRule(
            id: -7,
            enable: false,
            name: "数字混合(纯数字标题)",
            rule: #"(?<=[　\s])[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟\d]{1,12}[ 　\t]{0,4}$"#,
            serialNumber: 6
        ),
        TxtTocRule(
            id: -8,
            enable: true,
            name: "数字 分隔符 标题名称",
            rule: #"^[ 　\t]{0,4}\d{1,5}[:：,.， 、_—\-].{1,30}$"#,
            serialNumber: 7
        ),
        TxtTocRule(
            id: -9,
            enable: true,
            name: "大写数字 分隔符 标题名称",
            rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?)[ 、_—\-].{1,30}$"#,
            serialNumber: 8
        ),
        TxtTocRule(
            id: -10,
            enable: false,
            name: "数字混合 分隔符 标题名称",
            rule: #"^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章?[ 、_—\-]|\d{1,5}章?[:：,.， 、_—\-]).{0,30}$"#,
            serialNumber: 9
        ),
        TxtTocRule(
            id: -11,
            enable: true,
            name: "正文 标题/序号",
            rule: #"^[ 　\t]{0,4}正文[ 　]{1,4}.{0,20}$"#,
            serialNumber: 10
        ),
        TxtTocRule(
            id: -12,
            enable: true,
            name: "Chapter/Section/Part/Episode 序号 标题",
            rule: #"^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO][.、]|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,30}$"#,
            serialNumber: 11
        ),
        TxtTocRule(
            id: -13,
            enable: false,
            name: "Chapter(去简介)",
            rule: #"^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][Oo]\.|[Ee]pisode)\s{0,4}\d{1,4}.{0,30}$"#,
            serialNumber: 12
        ),
        TxtTocRule(
            id: -14,
            enable: true,
            name: "特殊符号 序号 标题",
            rule: #"(?<=[\s　])[【〔〖「『〈［\[](?:第|[Cc]hapter)[\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,10}[章节].{0,20}$"#,
            serialNumber: 13
        ),
        TxtTocRule(
            id: -15,
            enable: false,
            name: "特殊符号 标题(成对)",
            rule: #"(?<=[\s　]{0,4})(?:[\[〈「『〖〔《（【\(].{1,30}[\)】）》〕〗』」〉\]]?|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$"#,
            serialNumber: 14
        ),
        TxtTocRule(
            id: -16,
            enable: true,
            name: "特殊符号 标题(单个)",
            rule: #"(?<=[\s　]{0,4})(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$"#,
            serialNumber: 15
        ),
        TxtTocRule(
            id: -17,
            enable: true,
            name: "章/卷 序号 标题",
            rule: #"^[ \t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$"#,
            serialNumber: 16
        ),
        TxtTocRule(
            id: -18,
            enable: false,
            name: "顶格标题",
            rule: #"^\S.{1,20}$"#,
            serialNumber: 17
        ),
        TxtTocRule(
            id: -19,
            enable: false,
            name: "双标题(前向)",
            rule: #"(?m)(?<=[ \t　]{0,4})第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$(?=[\s　]{0,8}第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章)"#,
            serialNumber: 18
        ),
        TxtTocRule(
            id: -20,
            enable: false,
            name: "双标题(后向)",
            rule: #"(?m)(?<=[ \t　]{0,4}第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$[\s　]{0,8})第[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}章.{0,30}$"#,
            serialNumber: 19
        ),
        TxtTocRule(
            id: -21,
            enable: true,
            name: "书名 括号 序号",
            rule: #"^[一-龥]{1,20}[ 　\t]{0,4}[(（][\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\t]{0,4}$"#,
            serialNumber: 20
        ),
        TxtTocRule(
            id: -22,
            enable: true,
            name: "书名 序号",
            rule: #"^[一-龥]{1,20}[ 　\t]{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 　\t]{0,4}$"#,
            serialNumber: 21
        ),
        TxtTocRule(
            id: -23,
            enable: false,
            name: "特定字符 标题 特定符号",
            rule: #"(?<=\={3,6}).{1,40}?(?=\=)"#,
            serialNumber: 22
        ),
        TxtTocRule(
            id: -24,
            enable: true,
            name: "字数分割 分节阅读",
            rule: #"(?<=[ 　\t]{0,4})(?:.{0,15}分[页节章段]阅读[-_ ]|第\s{0,4}[\d零一二两三四五六七八九十百千万]{1,6}\s{0,4}[页节]).{0,30}$"#,
            serialNumber: 23
        ),
        TxtTocRule(
            id: -25,
            enable: false,
            name: "通用规则",
            rule: #"(?im)^.{0,6}(?:[引楔]子|正文(?!完|结)|[引序前]言|[序终]章|扉页|[上中下][部篇卷]|卷首语|后记|尾声|番外|={2,4}|第\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|页[、 　]|集(?![合和])|部(?![分是门落])|篇(?!张))).{0,40}$|^.{0,6}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟a-z]{1,8}[、. 　].{0,20}$"#,
            serialNumber: 24
        ),
    ]

    static let enabled: [TxtTocRule] = defaults.filter(\.enable)

    func regex() -> NSRegularExpression? {
        try? NSRegularExpression(pattern: rule, options: [.anchorsMatchLines])
    }
}
