"""Writes queries.jsonl: searches over the synthetic journal, with relevance defined by topic tags.

kind: exact (words likely in the text), part (part of a compound / short form), paraphrase (German, other
words), english, question, combo (two topics, all must be tagged), none (topic never mentioned: no answer).
"""
import json, pathlib

Q = {
 "person:lea": [("exact","Lea"),("paraphrase","meine Freundin"),("english","my girlfriend"),("question","Wann hatte ich Streit mit meiner Partnerin?")],
 "person:anna": [("exact","Anna"),("paraphrase","meine große Schwester"),("english","my sister"),("question","Was gibt es Neues von meiner Schwester?")],
 "person:mama": [("exact","Mama"),("part","Mutti"),("paraphrase","Telefonat mit meiner Mutter"),("english","my mom")],
 "person:oma": [("exact","Oma"),("paraphrase","Großmutter im Krankenhaus"),("english","grandma in hospital"),("question","Wie geht es Oma nach dem Sturz?")],
 "person:tobi": [("exact","Tobi"),("paraphrase","mein bester Kumpel"),("english","my best friend")],
 "person:sven": [("exact","Sven"),("paraphrase","mein Chef"),("english","my team lead"),("question","Was hat mein Teamlead gesagt?")],
 "person:dr-weber": [("exact","Dr. Weber"),("paraphrase","Therapiesitzung"),("english","therapy session"),("question","Was habe ich in der Therapie gelernt?")],
 "place:isar": [("exact","Isar"),("paraphrase","am Fluss spazieren"),("english","walk by the river")],
 "place:office": [("exact","Büro"),("paraphrase","im Großraumbüro"),("english","at the office")],
 "place:flat-giesing": [("exact","Giesing"),("paraphrase","alte Wohnung und Vermieter"),("english","my old apartment")],
 "place:new-flat": [("exact","Haidhausen"),("paraphrase","neue Wohnung mit Balkon"),("english","our new place")],
 "place:regensburg": [("exact","Regensburg"),("paraphrase","Besuch bei der Familie zuhause"),("english","visiting my hometown")],
 "place:lisbon": [("exact","Lissabon"),("paraphrase","Urlaub in Portugal"),("english","Lisbon trip")],
 "place:alps": [("exact","Alpen"),("part","Berge"),("paraphrase","Wanderung auf einen Gipfel"),("english","hiking in the mountains")],
 "work:launch": [("exact","Launch"),("paraphrase","Veröffentlichung der App"),("english","release day"),("question","Wie lief der Launch?")],
 "work:stress": [("exact","Stress bei der Arbeit"),("part","Überstunden"),("paraphrase","zu viel zu tun im Job"),("english","overwhelmed at work")],
 "work:salary": [("exact","Gehaltsverhandlung"),("part","Gehalt"),("paraphrase","mehr Geld verdienen"),("english","asking for a raise")],
 "work:ai-worries": [("exact","KI"),("paraphrase","Angst dass Maschinen meinen Job übernehmen"),("english","will AI replace designers")],
 "health:sleep": [("exact","schlecht geschlafen"),("part","Schlaf"),("paraphrase","nachts wach liegen"),("english","insomnia"),("question","Wann konnte ich nicht schlafen?")],
 "health:running": [("exact","Laufen"),("part","Lauftraining"),("paraphrase","joggen gehen"),("english","running training")],
 "health:knee": [("exact","Knie"),("part","Knieschmerzen"),("paraphrase","Verletzung beim Sport"),("english","knee pain")],
 "health:burnout": [("exact","Burnout"),("paraphrase","völlig ausgebrannt und leer"),("english","exhausted and empty"),("question","Wann ging gar nichts mehr?")],
 "home:heating": [("exact","Heizung"),("part","Heizkörper"),("paraphrase","Wohnung ist kalt"),("english","the heating is broken")],
 "home:moving": [("exact","Umzug"),("part","Kartons"),("paraphrase","zusammenziehen und Wohnungssuche"),("english","moving in together")],
 "home:balcony-plants": [("exact","Tomaten"),("part","Basilikum"),("paraphrase","Pflanzen auf dem Balkon"),("english","balcony garden")],
 "money:taxes": [("exact","Steuererklärung"),("part","Steuer"),("paraphrase","Papierkram fürs Finanzamt"),("english","tax return")],
 "money:worries": [("exact","Geldsorgen"),("paraphrase","reicht das Geld für die Miete"),("english","money worries")],
 "feeling:anxiety": [("exact","Angst"),("part","Zukunftsangst"),("paraphrase","Gedankenkreisen und Sorgen"),("english","anxious about the future")],
 "feeling:gratitude": [("exact","dankbar"),("paraphrase","schöner Moment heute"),("english","grateful")],
 "feeling:loneliness": [("exact","einsam"),("paraphrase","allein fühlen obwohl Leute da sind"),("english","lonely")],
 "feeling:anger": [("exact","wütend"),("paraphrase","total genervt und sauer"),("english","so angry")],
 "hobby:guitar": [("exact","Gitarre"),("part","Akkorde"),("paraphrase","Instrument üben"),("english","guitar practice")],
 "hobby:cooking": [("exact","gekocht"),("part","Rezept"),("paraphrase","Abendessen selbst gemacht"),("english","cooking dinner")],
 "hobby:reading": [("exact","Buch"),("paraphrase","was ich gerade lese"),("english","the book I'm reading")],
 "event:christmas": [("exact","Weihnachten"),("paraphrase","Feiertage bei der Familie"),("english","christmas")],
 "event:tobi-birthday": [("exact","Geburtstag von Tobi"),("paraphrase","Party zum 35."),("english","Tobi's birthday party")],
 "event:half-marathon": [("exact","Halbmarathon"),("paraphrase","das Rennen über 21 Kilometer"),("english","race day"),("question","Wie lief der Halbmarathon?")],
 "event:baby-mila": [("exact","Mila"),("part","Nichte"),("paraphrase","Baby ist da, ich bin Onkel"),("english","my niece was born")],
 "dream": [("exact","geträumt"),("part","Traum"),("paraphrase","heute Nacht hatte ich so einen komischen Traum"),("english","I had a dream")],
}
COMBOS = [
 (["person:lea","home:moving"], "mit Lea zusammenziehen"),
 (["person:lea","place:lisbon"], "Urlaub mit Lea"),
 (["person:oma","event:christmas"], "Oma an Weihnachten"),
 (["person:sven","work:salary"], "Gehaltsgespräch mit Sven"),
 (["health:knee","health:running"], "Knie beim Laufen"),
 (["person:anna","event:baby-mila"], "Annas Baby"),
 (["work:stress","health:sleep"], "wegen der Arbeit nicht schlafen"),
 (["person:dr-weber","feeling:anxiety"], "über meine Angst in der Therapie gesprochen"),
 (["home:heating","place:flat-giesing"], "Vermieter wegen der Heizung"),
 (["money:worries","home:moving"], "Kaution und Umzugskosten"),
]
NONE = [
 "Segeltörn","mein Hund","Schach spielen","Bitcoin kaufen","Urlaub in Italien","Hochzeit planen","Klavierstunde",
 "Skifahren","Autounfall","Bundestagswahl","Schrebergarten","Japanisch lernen","unsere Katze","Wochenende in Paris",
 "neues Tattoo","sailing trip","walking the dog","chess tournament","crypto portfolio","wedding planning",
 "piano lesson","ski holiday","car crash","election results","Rom","Venedig","Pizza in Neapel","Hundeschule",
 "Schachbrett","Börse und Aktien",
]

out = pathlib.Path(__file__).with_name("queries.jsonl")
rows, n = [], 0
for topic, items in Q.items():
    for kind, text in items:
        n += 1; rows.append({"id": f"q{n:03}", "text": text, "kind": kind, "all_topics": [topic]})
for topics, text in COMBOS:
    n += 1; rows.append({"id": f"q{n:03}", "text": text, "kind": "combo", "all_topics": topics})
for text in NONE:
    n += 1; rows.append({"id": f"q{n:03}", "text": text, "kind": "none", "all_topics": []})
out.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows), encoding="utf-8")
print(len(rows), "queries")
