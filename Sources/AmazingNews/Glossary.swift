import Foundation

/// Plain-English explanations for AI jargon that shows up in stories.
enum Glossary {
    /// (term shown, regex that finds it, explanation)
    static let entries: [(term: String, pattern: String, meaning: String)] = [
        ("LLM", #"\bLLMs?\b|large language models?"#, "Large language model: an AI trained on huge amounts of text to predict and write language — the engine behind ChatGPT, Claude and Gemini."),
        ("Open-weight", #"open[- ]weights?"#, "A model whose trained 'weights' are published, so anyone can download and run or modify it on their own hardware."),
        ("Open source", #"open[- ]source (model|AI)s?"#, "AI released with its code (and usually weights) public. Often used loosely to mean open-weight."),
        ("Agentic", #"\bagentic\b"#, "AI that takes actions on its own — clicking, browsing, running code, booking things — rather than just answering questions."),
        ("AI agent", #"\bAI agents?\b"#, "An AI system that carries out multi-step tasks for you, using tools like a browser or apps, with some independence."),
        ("Multimodal", #"\bmultimodal\b"#, "Works with more than one kind of input or output — text, images, audio, video — in the same model."),
        ("Diffusion model", #"\bdiffusion models?\b"#, "The technique behind most image and video generators: start from noise and repeatedly 'denoise' it into a picture."),
        ("Inference", #"\binference\b"#, "Running a trained model to get answers. Training builds the model; inference is using it (and it's what most AI computing bills are for)."),
        ("Fine-tuning", #"\bfine[- ]tun(e|ed|ing)\b"#, "Extra training on a smaller, specific dataset to specialise a model — e.g. teaching it a studio's style."),
        ("Parameters", #"\b\d+(\.\d+)?\s?(billion|trillion|[BT])[- ]parameters?\b|\bparameters\b"#, "The internal numbers a model learns during training. More parameters usually means more capable — and more expensive to run."),
        ("Tokens", #"\btokens?\b"#, "The chunks of text (roughly ¾ of a word) that models read and write. AI pricing and limits are counted in tokens."),
        ("Context window", #"\bcontext windows?\b"#, "How much text a model can consider at once — its working memory, measured in tokens."),
        ("Benchmark", #"\bbenchmarks?\b"#, "A standard test used to compare models. Useful, but labs often pick the ones they score well on."),
        ("Hallucination", #"\bhallucinat\w*"#, "When an AI states something false with confidence — an invented fact, quote or source."),
        ("Reasoning model", #"\breasoning models?\b"#, "A model that 'thinks' step by step before answering, trading speed and cost for accuracy on hard problems."),
        ("RAG", #"\bRAG\b|retrieval[- ]augmented"#, "Retrieval-augmented generation: the AI looks things up in your documents first, then answers using what it found."),
        ("GPU", #"\bGPUs?\b"#, "Graphics processing unit. Originally for rendering; now the main chip used to train and run AI — hence Nvidia's boom."),
        ("TPU", #"\bTPUs?\b"#, "Tensor processing unit: Google's own AI chip, an alternative to Nvidia GPUs."),
        ("Compute", #"\bcompute\b"#, "Industry shorthand for computing power — the chips, data centers and electricity needed for AI."),
        ("Frontier model", #"\bfrontier (AI|models?|labs?)\b"#, "The most capable AI models at any moment, from labs like OpenAI, Anthropic and Google DeepMind."),
        ("AGI", #"\bAGI\b|artificial general intelligence"#, "Artificial general intelligence: a hypothetical AI as capable as people across most tasks. There's no agreed definition."),
        ("Alignment", #"\balignment\b|\baligned\b"#, "Research on making AI systems reliably do what people intend, and avoid harmful behaviour."),
        ("Guardrails", #"\bguardrails?\b"#, "Rules and filters that stop an AI from producing harmful or off-limits content."),
        ("Text-to-video", #"text[- ]to[- ]video"#, "Generating video clips from a written description."),
        ("Image-to-video", #"image[- ]to[- ]video"#, "Animating a still image into a video clip — handy for previs and mood pieces."),
        ("Deepfake", #"\bdeepfakes?\b"#, "AI-made video, audio or images that convincingly impersonate a real person."),
        ("Synthetic data", #"\bsynthetic data\b"#, "Training data made by AI or simulation rather than collected from the real world."),
        ("Distillation", #"\bdistill(ation|ed|ing)?\b"#, "Training a smaller, cheaper model to imitate a bigger one."),
        ("MCP", #"\bMCP\b|Model Context Protocol"#, "Model Context Protocol: an open standard that lets AI assistants plug into apps and tools (e.g. Premiere, Nuke, Slack)."),
        ("API", #"\bAPIs?\b"#, "Application programming interface: how software talks to an AI service. Developers pay per use."),
        ("Foundation model", #"\bfoundation models?\b"#, "A large general-purpose model that other products are built on top of."),
        ("Transformer", #"\btransformers?\b"#, "The neural-network design (from Google, 2017) underneath almost all modern AI language and video models."),
        ("LoRA", #"\bLoRAs?\b"#, "A lightweight add-on that fine-tunes an image or video model to a specific character, style or product."),
        ("World model", #"\bworld models?\b"#, "AI that simulates how a 3D environment behaves over time — aimed at games, robotics and virtual production."),
        ("Gaussian splatting", #"gaussian splat\w*|\bsplats?\b"#, "A fast way to capture and render real scenes in 3D from photos or video — an alternative to photogrammetry."),
        ("NeRF", #"\bNeRFs?\b"#, "Neural radiance field: AI that rebuilds a 3D scene from a set of photos."),
        ("Upscaling", #"\bupscal\w*"#, "Using AI to increase image or video resolution while adding plausible detail."),
        ("Inpainting", #"\b(in|out)paint\w*"#, "AI filling in (inpainting) or extending (outpainting) part of an image — cleanup and set extension, AI-style."),
        ("Data center", #"\bdata cent(er|re)s?\b"#, "Warehouse-scale buildings full of servers. AI is driving a boom in them, and in their power use."),
        ("Export controls", #"\bexport controls?\b"#, "Government limits on selling advanced chips or technology to certain countries, mainly China."),
    ]

    private static let compiled: [(String, NSRegularExpression, String)] = entries.compactMap { e in
        (try? NSRegularExpression(pattern: e.pattern, options: .caseInsensitive)).map { (e.term, $0, e.meaning) }
    }

    /// Up to `limit` jargon terms found in the story, in order of first appearance.
    static func terms(in story: Story, limit: Int = 4) -> [(term: String, meaning: String)] {
        let text = [story.title, story.summary, story.why ?? ""].joined(separator: " ")
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        let found = compiled.compactMap { term, re, meaning -> (Int, String, String)? in
            re.firstMatch(in: text, range: range).map { ($0.range.location, term, meaning) }
        }
        return found.sorted { $0.0 < $1.0 }.prefix(limit).map { ($0.1, $0.2) }
    }
}
