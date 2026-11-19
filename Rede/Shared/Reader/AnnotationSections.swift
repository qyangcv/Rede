struct AnnotationSections {
    struct Section: Identifiable {
        let id: String
        let chapter: EpubTocEntry?
        var annotations: [Annotation]

        var title: String? { chapter?.title }
    }

    private let chapters: [String: EpubTocEntry]

    init(toc: [TOCItem]) {
        chapters = Dictionary(uniqueKeysWithValues: toc.compactMap { item in
            item.path.first.map { (item.id, $0) }
        })
    }

    func sections(for annotations: [Annotation]) -> [Section] {
        var sections: [Section] = []
        for annotation in annotations {
            let chapter = annotation.tocID.flatMap { chapters[$0] }.flatMap { $0.title.isEmpty ? nil : $0 }
            if sections.isEmpty || sections[sections.count - 1].chapter?.id != chapter?.id {
                sections.append(Section(id: annotation.id, chapter: chapter, annotations: []))
            }
            sections[sections.count - 1].annotations.append(annotation)
        }
        return sections
    }
}
