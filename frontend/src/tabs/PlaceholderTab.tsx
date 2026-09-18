type Props = { title: string; notebookHint?: string }

export default function PlaceholderTab({ title, notebookHint }: Props) {
  return (
    <div className="glass rounded-2xl p-8 max-w-2xl mx-auto text-center space-y-4">
      <h2 className="text-2xl font-bold text-amber-200">{title}</h2>
      <p className="text-slate-300 text-lg">בקרוב — תוכן ממחברת NotebookLM</p>
      {notebookHint && (
        <p className="text-slate-500 text-sm">{notebookHint}</p>
      )}
      <div className="mt-6 h-24 rounded-xl bg-gradient-to-l from-slate-800/80 to-slate-900/80 border border-slate-700/50 flex items-center justify-center text-slate-600">
        Placeholder
      </div>
    </div>
  )
}
