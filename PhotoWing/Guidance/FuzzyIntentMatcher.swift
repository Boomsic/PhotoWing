import Foundation

// MARK: - 多级模糊匹配引擎

/// 解决"她说得不标准"的问题
/// 不依赖纯 contains，而是 5 级匹配管线：
/// 精确→N-gram→编辑距离→拼音→同义词→兜底
struct FuzzyIntentMatcher {

    // MARK: - 匹配结果

    struct MatchResult {
        let matchedToken: String       // 匹配到的原始 token
        let canonicalToken: String     // 归一化后的标准词
        let dimension: WritableKeyPath<AestheticIntent, Double>
        let value: Double              // 维度强度
        let confidence: Double         // 匹配置信度 0-1
        let matchLevel: MatchLevel     // 在哪一级匹配到的

        enum MatchLevel: Int, Comparable {
            case exact = 5       // 精确匹配
            case ngram = 4       // N-gram 匹配
            case editDistance = 3 // 编辑距离 ≤ 2
            case pinyin = 2      // 拼音相似
            case synonym = 1     // 同义词
            case fallback = 0    // 兜底

            static func < (lhs: MatchLevel, rhs: MatchLevel) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }
    }

    // MARK: - 扩大的关键词库（含同义词组）

    /// 每个维度有多个同义词组，每组内的词等价
    /// 格式：维度 → [[标准词, 同义词1, 同义词2, ...], ...]
    private static let synonymGroups: [(
        dimension: WritableKeyPath<AestheticIntent, Double>,
        groups: [[String]],
        baseValue: Double
    )] = [
        // ── 身体比例 ──
        (\.bodyProportion, [
            ["腿长", "长腿", "大长腿", "腿显长", "显腿长", "拉长腿", "推长", "退长", "腿常", "条儿顺", "腿线好"],
            ["腿拉长", "把腿拉长", "拉腿", "腿拍长", "腿显长一点"],
            ["显高", "显瘦", "拉高", "修长", "高挑", "苗条", "显条", "苗条身材", "身材好"],
            ["显矮", "显胖", "压个子", "压身高", "拍矮了", "显得矮"],
            ["比例好", "黄金比例", "九头身", "头身比", "身材比例"],
            ["脚贴底", "脚在底下", "踩底线", "脚踩边"],
        ], 0.85),
        (\.bodyProportion, [
            ["娇小", "小巧", "小鸟依人", "可爱身高", "小个子"],
            ["矮", "短腿", "腿短", "五五分"],
        ], -0.5),

        // ── 面部渲染 ──
        (\.faceRendering, [
            ["脸小", "显脸小", "瘦脸", "小脸", "巴掌脸", "瓜子脸", "连小", "脸晓", "脸显小", "脸瘦"],
            ["脸大", "显脸大", "大脸", "圆脸", "肉脸", "脸圆", "嘟嘟脸", "娃娃脸"],
            ["五官立体", "轮廓深", "立体", "鼻梁高", "深邃", "欧式", "混血感"],
            ["侧脸", "侧面", "侧颜", "侧脸杀", "侧颜杀", "半边脸"],
            ["下颌线", "棱角", "锋利", "棱角分明", "下颚线"],
        ], 0.8),
        (\.faceRendering, [
            ["圆脸", "肉脸", "嘟嘟脸", "娃娃脸"],
            ["柔和", "温柔", "柔美", "脸部柔"],
        ], -0.5),

        // ── 色温 ──
        (\.colorWarmth, [
            ["暖调", "温暖", "暖色", "金色", "夕阳", "落日", "黄昏", "黄金时刻", "暖光", "黄调", "偏暖", "暖暖的"],
            ["日系暖", "胶片暖", "复古暖", "昭和暖"],
            ["冷调", "清冷", "冷色", "蓝调", "冰蓝", "冷光", "偏冷", "冷冷", "xing冷淡", "性冷淡"],
            ["欧美冷", "时尚冷", "北欧风", "极简冷"],
            ["青橙", "teal orange", "好莱坞", "橙青", "青橙调"],
            ["高级灰", "莫兰迪", "灰调", "低饱和"],
        ], 0.8),
        (\.colorWarmth, [
            ["冷调", "清冷", "蓝调", "冰蓝", "偏冷", "冷色"],
            ["欧美冷", "时尚冷", "北欧风"],
        ], -0.7),

        // ── 光影 ──
        (\.lightDrama, [
            ["光影", "戏剧光", "伦勃朗", "侧光", "硬光", "强光", "光线感", "光影感"],
            ["柔光", "软光", "散射光", "阴天", "漫射", "柔柔的", "柔和光"],
            ["平光", "均匀光", "证件照光", "平"],
            ["蝴蝶光", "派拉蒙", "美人光", "蝶光"],
            ["暗调", "暗黑", "dark", "暗系"],
            ["亮调", "明亮", "高调", "亮亮"],
            ["逆光", "背光", "逆光光", "背后有光"],
            ["顺光", "正面光", "迎着光"],
            ["氛围感", "氛围", "感觉"],
        ], 0.8),
        (\.lightDrama, [
            ["柔光", "软光", "散射光", "阴天", "漫射", "柔柔的"],
            ["平光", "均匀光", "证件照光"],
            ["顺光", "正面光", "迎着光"],
        ], -0.6),

        // ── 景深 ──
        (\.depthPreference, [
            ["虚化", "浅景深", "bokeh", "人像模式", "奶油般", "化开", "背景虚化", "背后模糊", "糊"],
            ["大景深", "全清楚", "都清楚", "深景深", "泛焦", "全都清楚", "前后都清晰"],
            ["背景干净", "简洁背景", "纯背景", "干净背景"],
            ["环境人像", "带景", "景物合一", "场景感", "带环境"],
            ["空气感", "空间感", "通透"],
        ], 0.85),
        (\.depthPreference, [
            ["大景深", "全清楚", "都清楚", "全都清晰", "泛焦"],
        ], -0.7),

        // ── 构图 ──
        (\.compositionDynamism, [
            ["三分法", "黄金分割", "偏一边", "不对称", "不在中间"],
            ["居中", "对称", "正中间", "证件照", "放中间"],
            ["对角线", "斜构图", "倾斜", "歪的", "斜的"],
            ["留白", "负空间", "空", "留空"],
            ["不看镜头", "看别处", "看远方", "看旁边", "不要看镜头", "别看镜头"],
            ["直视镜头", "看着镜头", "盯镜头", "看镜头", "看这里"],
            ["头顶留白", "头上留白", "头上空"],
        ], 0.6),
        (\.compositionDynamism, [
            ["居中", "对称", "正中间", "证件照", "放中间"],
            ["直视镜头", "看着镜头", "看镜头"],
        ], -0.6),

        // ── 质感 ──
        (\.textureQuality, [
            ["胶片", "颗粒", "胶卷", "film", "菲林", "底片", "胶片风", "胶片感"],
            ["柔焦", "柔光镜", "梦幻", "朦胧", "soft", "雾面", "柔化"],
            ["锐利", "高清", "数毛", "锐化", "超清", "细节"],
            ["数码", "干净", "清晰", "数字"],
            ["电影感", "cinematic", "大片", "电影质感", "电影风"],
            ["磨皮", "柔肤", "美颜", "皮肤好"],
            ["质感", "肌理", "纹理"],
        ], 0.8),
        (\.textureQuality, [
            ["柔焦", "柔光镜", "梦幻", "朦胧", "soft"],
            ["数码", "干净", "数字"],
            ["磨皮", "美颜"],
        ], -0.5),

        // ── 动态 ──
        (\.dynamismLevel, [
            ["抓拍", "偷拍", "不经意", "自然抓拍", "candid", "随意拍", "随手拍"],
            ["摆拍", "pose", "定住", "别动", "摆好", "站好"],
            ["走路", "走", "迈步", "行", "走起来", "走一下"],
            ["回眸", "回头", "转身", "回个头", "回身"],
            ["跳跃", "跳", "飞", "跳起来", "蹦"],
            ["甩头发", "撩头发", "撩发", "甩头", "拨头发"],
            ["跑", "奔跑", "跑起来"],
            ["舞蹈", "跳舞", "舞动", "翩翩"],
            ["坐着", "坐", "靠", "倚", "坐下"],
            ["转圈", "旋转"],
        ], 0.8),
        (\.dynamismLevel, [
            ["摆拍", "pose", "定住", "别动", "摆好"],
            ["坐着", "坐", "靠", "倚"],
        ], -0.6),

        // ── 年代 ──
        (\.eraStyle, [
            ["复古", "vintage", "怀旧", "老照片", "旧时代", "古着", "老旧"],
            ["港风", "港片", "王家卫", "重庆森林", "港式", "港味", "港"],
            ["昭和", "日式复古", "和风复古", "昭和风"],
            ["民国", "旗袍", "老上海", "民国风"],
            ["90年代", "80年代", "70年代", "千禧年", "y2k", "九零", "八零"],
            ["法式", "法式复古", "巴黎", "法国风"],
            ["美式", "美式复古", "加州", "美式风"],
            ["韩式", "韩风", "韩系", "韩"],
        ], 0.8),
        (\.eraStyle, [
            ["现代", "当代", "潮流", "时髦", "modern", "时尚"],
            ["科技感", "赛博", "未来感", "cyberpunk", "赛博朋克"],
        ], -0.7),

        // ── 情绪 ──
        (\.emotionalTone, [
            ["日系", "小清新", "清新", "淡雅", "文艺", "森系", "日式清新"],
            ["韩系", "韩式", "韩风"],
            ["甜美", "甜", "可爱", "萌", "元气", "甜妹", "甜甜", "甜美的"],
            ["高冷", "冷淡", "不笑", "酷", "飒", "冷艳", "冷脸", "高冷范", "冷"],
            ["性感", "妩媚", "魅惑", "成熟", "撩人", "sexy"],
            ["知性", "优雅", "气质", "端庄", "大气", "知性美"],
            ["梦幻", "童话", "仙境", "仙女", "梦幻感", "仙"],
            ["忧郁", "悲伤", "情绪", "孤独", "emo", "忧郁感", "伤感"],
            ["开心", "快乐", "笑容", "笑着", "笑", "灿烂"],
            ["自然", "生活化", "日常", "随性", "自然点", "随意"],
            ["ins风", "网红风", "小红书", "红书风"],
            ["高级感", "时尚大片", "杂志风", "杂志感", "高级"],
            ["暗黑", "哥特", "阴郁", "黑暗", "暗系"],
            ["治愈", "温暖", "温柔"],
        ], 0.7),
        (\.emotionalTone, [
            ["高冷", "冷淡", "不笑", "酷", "飒", "冷艳"],
            ["暗黑", "哥特", "阴郁"],
            ["高级感", "时尚大片", "杂志风"],
        ], -0.7),
    ]

    // MARK: - 5 级匹配管线

    func matchAll(in text: String) -> [MatchResult] {
        var results: [MatchResult] = []
        let lower = text.lowercased()

        for (dimension, groups, baseValue) in Self.synonymGroups {
            for group in groups {
                // Level 1: 精确匹配
                if let result = exactMatch(in: lower, group: group, dimension: dimension, value: baseValue) {
                    results.append(result)
                    continue
                }

                // Level 2: N-gram 滑动窗口
                if let result = ngramMatch(in: lower, group: group, dimension: dimension, value: baseValue) {
                    results.append(result)
                    continue
                }

                // Level 3: 编辑距离 ≤ 2
                if let result = editDistanceMatch(in: lower, group: group, dimension: dimension, value: baseValue) {
                    results.append(result)
                    continue
                }

                // Level 4: 拼音相似
                if let result = pinyinMatch(in: lower, group: group, dimension: dimension, value: baseValue) {
                    results.append(result)
                    continue
                }

                // Level 5: 分字匹配（拆分后部分命中）
                if let result = splitCharMatch(in: lower, group: group, dimension: dimension, value: baseValue) {
                    results.append(result)
                    continue
                }
            }
        }

        // 去重（同一维度取最高置信度的结果）
        results = deduplicate(results)

        return results
    }

    // MARK: - Level 1: 精确匹配

    private func exactMatch(in text: String, group: [String],
                            dimension: WritableKeyPath<AestheticIntent, Double>,
                            value: Double) -> MatchResult? {
        for token in group {
            if text.contains(token) {
                let modifier = findModifier(in: text, around: token)
                return MatchResult(
                    matchedToken: token, canonicalToken: group[0],
                    dimension: dimension, value: value * modifier,
                    confidence: 1.0, matchLevel: .exact
                )
            }
        }
        return nil
    }

    // MARK: - Level 2: N-gram 滑动窗口

    private func ngramMatch(in text: String, group: [String],
                             dimension: WritableKeyPath<AestheticIntent, Double>,
                             value: Double) -> MatchResult? {
        // 对输入文本生成 2-gram 和 3-gram
        let chars = Array(text)
        guard chars.count >= 2 else { return nil }

        var ngrams: [String] = []
        for i in 0..<(chars.count - 1) {
            ngrams.append(String(chars[i...i+1]))  // 2-gram
            if i + 2 < chars.count {
                ngrams.append(String(chars[i...i+2]))  // 3-gram
            }
        }

        // 检查是否有 ngram 与关键词匹配
        for token in group {
            let tokenChars = Array(token)
            for ngram in ngrams {
                if ngram == token {
                    let modifier = findModifier(in: text, around: ngram)
                    return MatchResult(
                        matchedToken: ngram, canonicalToken: group[0],
                        dimension: dimension, value: value * modifier,
                        confidence: 0.85, matchLevel: .ngram
                    )
                }
                // 部分重叠（3-gram 包含 2-gram 关键词）
                if tokenChars.count == 2 && ngram.count == 3 && ngram.contains(token) {
                    return MatchResult(
                        matchedToken: token, canonicalToken: group[0],
                        dimension: dimension, value: value * 0.8,
                        confidence: 0.7, matchLevel: .ngram
                    )
                }
            }
        }

        // 跨词匹配："腿能不能显得长" → 找到"腿"和"长"在 5 字窗口内
        for token in group where token.count == 2 {
            let c1 = token.first!, c2 = token.last!
            if let idx1 = chars.firstIndex(of: c1),
               let idx2 = chars.lastIndex(of: c2),
               abs(idx1.distance(to: idx2)) <= 6 {
                return MatchResult(
                    matchedToken: token, canonicalToken: group[0],
                    dimension: dimension, value: value * 0.7,
                    confidence: 0.6, matchLevel: .ngram
                )
            }
        }

        return nil
    }

    // MARK: - Level 3: 编辑距离

    private func editDistanceMatch(in text: String, group: [String],
                                    dimension: WritableKeyPath<AestheticIntent, Double>,
                                    value: Double) -> MatchResult? {
        let chars = Array(text)
        guard chars.count >= 2 else { return nil }

        // 生成所有 2-4 字滑动窗口
        var windows: [String] = []
        for len in 2...4 {
            for i in 0...(chars.count - len) {
                windows.append(String(chars[i..<i+len]))
            }
        }

        var bestMatch: (token: String, window: String, dist: Int, conf: Double)? = nil

        for token in group {
            for window in windows {
                let dist = levenshtein(token, window)
                let maxLen = max(token.count, window.count)
                let similarity = 1.0 - Double(dist) / Double(maxLen)

                if dist <= 2 && similarity > 0.5 {
                    let conf = similarity * 0.85
                    if conf > (bestMatch?.conf ?? 0) {
                        bestMatch = (token, window, dist, conf)
                    }
                }
            }
        }

        if let bm = bestMatch {
            return MatchResult(
                matchedToken: bm.window, canonicalToken: group[0],
                dimension: dimension, value: value * bm.conf,
                confidence: bm.conf, matchLevel: .editDistance
            )
        }

        return nil
    }

    /// 标准 Levenshtein 距离
    private func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1), b = Array(s2)
        var dp = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dp[i][0] = i }
        for j in 0...b.count { dp[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                dp[i][j] = a[i-1] == b[j-1]
                    ? dp[i-1][j-1]
                    : min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1]) + 1
            }
        }
        return dp[a.count][b.count]
    }

    // MARK: - Level 4: 拼音相似

    private func pinyinMatch(in text: String, group: [String],
                              dimension: WritableKeyPath<AestheticIntent, Double>,
                              value: Double) -> MatchResult? {
        // 简化拼音匹配：常见谐音字映射表
        let homophoneGroups: [[String]] = [
            ["腿", "推", "退", "颓"],          // tui
            ["脸", "连", "怜", "联"],          // lian
            ["长", "常", "尝", "场"],          // chang
            ["光", "广", "逛"],                // guang
            ["暖", "男"],                      // nuan/nan 接近
            ["小", "晓", "笑"],                // xiao
            ["高", "告", "糕"],                // gao
            ["冷", "楞"],                      // leng
            ["清", "轻", "情"],                // qing
            ["日", "一"],                      // ri/yi 部分方言混
            ["系", "细", "西"],                // xi
            ["风", "封", "峰"],                // feng
            ["感", "敢", "赶"],                // gan
            ["酷", "库", "苦"],                // ku
        ]

        for token in group {
            let tokenChars = Array(token)
            // 尝试替换每个字为谐音字
            for hg in homophoneGroups {
                for i in 0..<tokenChars.count {
                    for homophone in hg where homophone != String(tokenChars[i]) {
                        var modified = tokenChars
                        modified[i] = Character(homophone)
                        let homophoneToken = String(modified)
                        if text.contains(homophoneToken) {
                            return MatchResult(
                                matchedToken: homophoneToken, canonicalToken: group[0],
                                dimension: dimension, value: value * 0.65,
                                confidence: 0.55, matchLevel: .pinyin
                            )
                        }
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Level 5: 分字匹配

    private func splitCharMatch(in text: String, group: [String],
                                 dimension: WritableKeyPath<AestheticIntent, Double>,
                                 value: Double) -> MatchResult? {
        // "腿长" → 检查"腿"和"长"是否都在文本中（不管位置）
        for token in group where token.count >= 2 {
            let chars = Array(token)
            let allPresent = chars.allSatisfy { text.contains(String($0)) }
            if allPresent {
                return MatchResult(
                    matchedToken: token, canonicalToken: group[0],
                    dimension: dimension, value: value * 0.5,
                    confidence: 0.4, matchLevel: .fallback
                )
            }
        }
        return nil
    }

    // MARK: - 去重

    private func deduplicate(_ results: [MatchResult]) -> [MatchResult] {
        var best: [ObjectIdentifier: MatchResult] = [:]

        for r in results {
            let key = ObjectIdentifier(r.dimension as AnyKeyPath as AnyObject)
            if let existing = best[key] {
                if r.matchLevel > existing.matchLevel ||
                   (r.matchLevel == existing.matchLevel && r.confidence > existing.confidence) {
                    best[key] = r
                }
            } else {
                best[key] = r
            }
        }

        return Array(best.values)
    }

    // MARK: - 强度修饰符

    private let modifiers: [(String, Double)] = [
        ("非常", 1.5), ("特别", 1.5), ("很", 1.3), ("好", 1.2),
        ("超级", 1.8), ("极其", 1.8), ("太", 1.5), ("巨", 1.5),
        ("贼", 1.4), ("老", 1.3), ("挺", 1.1),
        ("稍微", 0.5), ("一点", 0.6), ("一点点", 0.4), ("略微", 0.4),
        ("有点", 0.6), ("不那么", -0.5), ("别太", -0.7), ("不要太", -0.7),
        ("能不能", 1.0), ("可以", 1.0), ("想要", 1.0), ("要", 1.0),
    ]

    private func findModifier(in text: String, around token: String) -> Double {
        guard let range = text.range(of: token) else { return 1.0 }
        let prefix = String(text[..<range.lowerBound].suffix(4))
        for (mod, mult) in modifiers {
            if prefix.contains(mod) { return mult }
        }
        return 1.0
    }
}
