alias Tiago.Repo
alias Tiago.Organizations.Organization
alias Tiago.Parties
alias Tiago.Accounting

Repo.transaction(fn ->
  org = Repo.insert!(%Organization{name: "RP PLASTIC AND METAL", gstn: "04CBQPK2927R1ZY"})
  Accounting.setup_default_accounts(org.id)

  parties = [
    {"A.B. SPRING CO.", :customer, ["04AISPR1791H1ZT"]},
    {"CMS INDUSTRIES", :customer, ["04CPNPS4589E1ZD"]},
    {"DNA EXPERT SERVICES", :customer, ["04AADFD3584D1ZT"]},
    {"M/S EFFICIENT ENGINEERING AND TRADING CO", :customer, ["09CPJPS2198H1Z8"]},
    {"PARKASH PNG REGULATORS PRIVATE LIMITED", :customer, ["03AANCP0896P1ZP"]},
    {"TARUN ENGINEERS", :customer, ["03AZRPS3017P1ZT"]},
    {"RAMA INDUSTRIES", :customer, ["03BEYPS0995F1ZW"]},
    {"Sunder Enterprises", :customer, ["04EUQPK4087P1ZQ"]},
    {"sonu enterprises", :customer, ["03CMLPS2616B1ZD"]},
    {"BHASIN PACKARD ELECTRONICS P. LTD", :customer, ["03AAACB6151A1ZJ"]},
    {"Innow8", :customer, ["03AAHCI4955L1ZA"]},
    {"MANAV TRADING CO.", :customer, ["03ABXPL0702C1Z4"]},
    {"Brillpak Technologies", :customer, ["06AQZPR7067H1ZX"]},
    {"GOYAL AND SONS", :customer, ["03AJBPG2816J1ZO"]},
    {"S.D. ENGINEERING WORKS", :customer, ["04AFWPR8636Q1Z7"]},
    {"CROWN COFFEE MACHINE & COMM. KITCHEN EQUIPMENTS", :customer, ["03ADTPS7339C1ZA"]},
    {"QUICK SHOP", :customer, ["03BMVPN5530L1ZL"]},
    {"ENVIRONMENTAL & SCIENTIFIC INSTRUMENTS", :customer, ["06AAAFE5413B1Z7"]},
    {"MANU INTERNATIONAL", :customer, ["03AAEFM3348M1Z8"]},
    {"PAUL & PAUL ENTERPRISES", :customer, ["04AASPA2773L1ZI"]},
    {"H.M INDUSTRIES", :customer, ["02DDGPK4876J1ZB"]},
    {"URGENT ENGINEERING WORKS", :customer, ["04AMYPS6655H1Z9"]},
    {"S ELITE ENGINEERS AND PACKERS", :customer, ["03AIHPG8080B1ZP"]},
    {"Seven Star Scientific Instrument", :customer, ["04ACPFS4442K1ZS"]},
    {"AQUA CARE TECHINIQUE", :customer, ["06ADBPT1854H1ZJ"]},
    {"M/S RAMA HITEK ENGINEERS PVT. LTD", :customer, ["03AAECR3639P1Z1"]},
    {"PRABHA ELECTRONICS PVT LTD", :customer, ["03AADCP2295E1ZP"]},
    {"NAVEEN ENGINEERING WORKS", :customer, ["02AAJFN6385N1ZR"]},
    {"VISHESH ENGINEERING WORKS", :customer, ["04ASQPK4941C1ZU"]},
    {"PARAS ENGINEERS", :customer, ["04ANMPS1275J1ZO"]},
    {"SICKLE INNOVATIONS PRIVATE LIMITED", :customer, ["24AAUCS0888H1ZS"]},
    {"UNIVERSAL ELECTRONICS & TRANSFORMERS", :customer, ["03AIOPS1308K1Z6"]},
    {"A.K. PLAST INDUSTRIES", :customer, ["03ABGFA0747D1Z2"]},
    {"M/s Maurya Enterprises", :customer, ["04DAEPK4236F1Z2"]},
    {"MAANVI ENGG. WORKS", :customer, ["04DMOPK5392E1ZU"]},
    {"SHARMA PLASTIC ENTERPRISES", :customer, ["04BGOPS1847Q1ZK"]},
    {"CAPITAL INDUSTRIES", :customer, ["04AAMPD8244P1ZB"]},
    {"CHANDIGARH PLASTIC INDUSTRIES", :customer, ["04AFNPS5031B1ZR"]},
    {"PERFECT HYDRAULICS (P) LTD", :customer, ["04AACCP1102B1ZI"]},
    {"MECHATRONICS ENGINEERING WORKS", :customer, ["04ABFFM8701N1Z2"]},
    {"PERFECT OVERSEAS IMPEX", :customer, ["04EGKPS0245H1ZE"]},
    {"M/s Seven Star Scientific Instruments", :customer, ["06ACPFS4442K1ZO"]},
    {"KAPOTECH INDUSTRIES", :customer, ["03AGEPK4160B1Z4"]},
    {"Maurya Engineering Works", :customer, ["04AFQPM4124G1ZK"]},
    {"POWER PACKARD PVT LTD", :customer, ["03AAGCP5229D1ZS"]},
    {"DECIBEL DYNAMICS LIMITED", :customer, ["04AACCD6430G1Z3"]},
    {"ULTIMATE GYM SOLUTIONS", :customer, ["03BUBPG7429R1ZA"]},
    {"AVEER INDUSTRIES", :customer, ["03BAFPS0685B1Z0"]},
    {"Sickle Innovations Private Limited", :customer, ["36AAUCS0888H1ZN"]},
    {"SHARMA PLASTIC WORKS", :customer, ["04ALHPS5978H1ZK"]},
    {"MOVO ADVENTURES PRIVATE LIMITED", :both_customer_and_supplier, ["04AAECV7811P1ZX", "06AAECV7811P1ZT"]},
    {"CINE CITY PHOTO EQUIPMENT PVT. LTD.", :both_customer_and_supplier, ["04AADCC6180D1Z2"]},
    {"04AALPC5432F1Z6", :supplier, ["04AALPC5432F1Z6"]},
    {"04CLUPK0632F1Z8", :supplier, ["04CLUPK0632F1Z8"]},
    {"04AACFN5038M1Z8", :supplier, ["04AACFN5038M1Z8"]},
    {"SYNERGY INTACT PRIVATE LIMITED", :both_customer_and_supplier, ["03ABCCS3169A1ZU"]}
  ]

  Enum.each(parties, fn {name, type, gstns} ->
    {:ok, party} = Parties.create_party(org.id, %{name: name, type: type})
    Enum.each(gstns, fn gstn -> Parties.add_gstn_to_party(party.id, gstn) end)
  end)

  alias Tiago.Auth
  alias Tiago.Organizations
  
  {:ok, user} = Auth.register_user(%{
    email: "admin@example.com",
    password: "Password123!"
  })
  
  # Confirm user
  user = Auth.get_user!(user.id)
  user |> Ecto.Changeset.change(%{confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)}) |> Repo.update!()
  
  # add to org
  Organizations.create_membership(user.id, org.id, :admin)
end)
IO.puts("Done!")
