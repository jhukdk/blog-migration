---
title: "General Data Protection Regulation (GDPR) - The Law, Ethics, and its Fines"
date: 2022-01-29T13:01:00+00:00
slug: "general-data-protection-regulation-gdpr-an-overview-of-the-law-and-its-fines"
categories: ["Research", "Writeup"]
draft: false
---
In today's modern tech-centered business environment, corporations like Facebook, Google, and Amazon have collected extensive analytics of users' online digital behavior in order to build, maintain, and increase their market caps. Public scandals such as Facebook’s voluntary involvement with Cambridge Analytica clearly reveal that businesses have enormous financial incentives to gather, store, and sell the personally identifiable information of end users. Historically, the legal guidelines surrounding the processing of users' personal data has been lax. However, in response to this growing list of privacy concerns, European lawmakers passed and codified the General Data Protection Regulation (GDPR) on May 25th, 2018.



According to Article 5 of the GDPR, six specific guidelines have been laid out to serve as philosophical principles that collectively constitute data privacy. Those principles are **1.)** Fairness and lawfulness; **2.)** Purpose limitation; **3.)** Data minimization; **4.)** Accuracy; **5.)** Storage limitation; and **6.)** Integrity and confidentiality. (Goddard, 2017) Many of these data privacy and security principles will already be familiar to experienced cybersecurity professionals, however the explicit identification of these distinct principles into a single, written, legal document helps to clarify the complex issue of data privacy.



In addition to these 6 principles, GDPR also stipulates, guarantees, and enshrines certain functionalities to be "request-able" by end users. These many functional rights include the “right to erasure”, “right to access”, “right to rectification”, “right to data portability”, and also “right to restriction of processing.” (Bozhanov, 2018) This means that any business wishing to provide digital services in Europe should be aware that they must also figure out a way to implement these technical functionalities that can be requested by end users.



The exact method regarding how different organizations will choose to implement each of these GDPR requirements will be incumbent upon each individual organization and their technical engineering team to reach consensus and settle upon, then execute. This means that data privacy concepts can be instantiated in different programming languages, paradigms, and technology stacks according to the requirements of each particular business environment.



For example, if an EU business owner wants to implement the “right of erasure” into his database that contains the home address shipping information of his customers. Doing so would help fulfill the Article 5 GDPR guidelines of 3.) data minimization and even more directly 5.) storage limitation. A hypothetical means of implementing this functionality into programming code might entail establishing a policy for database data retention and deletion deadlines. For example, in the customer shipment and fulfillment space, databases storing shipping information could automatically schedule for job deletion a customer’s personal home address information once another API tracking system determines the shipment returns a successful value. (Bozhanov, 2018) Best practices for “pseudonymization” of users personal information, perhaps via the use of an encryption key or obfuscation algorithm, should also be implemented within organizational policies that better ensure non-attribution. (Politou, 2017)



Next, specific instructions have been laid out by GDPR that address the methods and means by which users can authoritatively provide **informed consent**, prior to collecting their personal data online. According to the Court of Justice of the EU, in order for consent to be freely given and informed, it must be a “separate action” from the activity the user was initially pursuing. (Nouwens, 2020) In other words, this means that passively browsing an online application does not constitute positive action and therefore does not provide meaningful informed consent. Instead, a user must provide explicit “opt-in” consent and a check-box must not automatically be filled in by default. (Nouwens, 2020)



In comparison to Europe, the United States has a very different outlook on an individual's data privacy. Unlike data protection laws found in Europe, those laws in the United States have been siloed into specific categories, in many cases corresponding to the particular business industry to which that data belongs.


> The categories covered under federal law are healthcare data (under the Health Information and Portability Accountability Act, HIPAA), financial data (under the Gramm Leach Bliley Act, GLB) children’s information (under the Children’s Online Privacy Protection Act, COPPA), students’ personal information (under Family Educational Rights and Privacy Act, FERPA), and consumer information (under the Fair Credit Reporting Act, FCRA).
>
> (Houser, Voss, 2018)



It is important to notice two points. First, many of these regulations were enacted prior to common use of the internet and cloud storage systems, and correspondingly do not map very intuitively to the current digital landscape in 2022. Second, many of these laws approach data protection from the perspective of businesses rather than consumers. While the EU seems to frame data protection in the GDPR from the fiduciary perspective of individuals, the United States has approached the same topic of data privacy from the perspective of corporations. These vast differences in privacy rights ideologies can be traced back to the expressed inclusion of a “right to privacy” in the Charter of Fundamental Rights of the European Union, whereas no such equivalent legal guarantee exists in the United States Constitution.



In a globalized economy and increasingly digital marketplace, it is difficult to avoid doing business with consumers located in various countries located across the world including the European Union. Despite this, there are many new business challenges that GDPR introduces to an already strained economic environment. Those include extraterritorial application of GDPR fines to data processors located outside the EU, specific functional rights granted to individual users (as previously discussed), and a host of new compliance mechanisms and audit-proof record-keeping requirements. (Rahman, 2018)



According to Article 83 of the GDPR, corporations found liable for violating the most serious category of data protection laws **will be fined** the higher of 20,000,000 EUR or 4% of their global annual revenue. This would entail a fine of $1 billion USD in the case of Facebook, or $3-4 billion USD in the case of Google/Alphabet. Such exorbitant fines represent a potential existential threat for Google’s future ability to operate in the European marketplace precisely because a significant portion of their revenue stems from selling targeted advertisements using the data collected from European users.



In 2014, the Italian Data Processing Authority (DPA) ordered Google to provide “more effective notices and obtain prior consent from its users for the processing of their personal information.” Upon a technical investigation, it was discovered that Google was processing information in Gmail accounts and using data found in cookies to profile users and sell targeted ads. (Houser, Voss, 2018) It remains to be seen whether Google and Facebook will successfully be able to adapt their data processing systems in order to maintain compliance with the European marketplace, or whether GDPR truly represents an existential threat to the future operations of their business model.



Since its introduction to the world on May 25th 2018, the General Data Protection Regulation has already had an enormous impact on the global digital economy, data privacy, and the field of cybersecurity. The impact of this legislation will continue to be felt into the next several years as privacy compliance requirements continue to evolve. It is important to pay attention to GDPR not only because the fines that can be imposed are substantial, but also because the data privacy practices implemented by global tech corporations merit greater scrutiny. The commodity these global tech giants sell after all, is our own personal data privacy.



References -



1.) Bozhanov, B. (2018, February 19). GDPR - A practical guide for developers and architects. AxonIQ. Retrieved November 22, 2021, from https://lp.axoniq.io/gdpr-data-protection-module.  
2.) GDPR Resources and Information. (n.d.). Article 5: Principles relating to processing of personal data. GDPR.org. Retrieved November 21, 2021, from https://www.gdpr.org/regulation/article-5.html.  
3.) Goddard, M. (2017). The EU General Data Protection Regulation (GDPR): European Regulation that has a Global Impact. International Journal of Market Research, 59(6), 703–705. https://doi.org/10.2501/IJMR-2017-050  
4.) Houser, K., & Voss, G. (2018, November 6). GDPR: The end of google and Facebook or a new paradigm in data privacy? Richmond Journal of Law and Technology. Retrieved November 21, 2021, from https://jolt.richmond.edu/gdpr-the-end-of-google-and-facebook-or-a-new-paradigm-in-data-privacy/.  
5.) Nouwens, M., Liccardi, I., & Veale, M. (2020, April 1). Dark patterns after the GDPR: Scraping consent pop-ups and demonstrating their influence. Dark Patterns after the GDPR: Scraping Consent Pop-ups and Demonstrating their Influence | Proceedings of the 2020 CHI Conference on Human Factors in Computing Systems. Retrieved November 21, 2021, from https://dl.acm.org/doi/abs/10.1145/3313831.3376321.  
6.) Politou, E., Alepis, E., & Patsakis, C. (2018, March 26). Forgetting personal data and revoking consent under the GDPR: Challenges and proposed solutions. OUP Academic. Retrieved November 21, 2021, from https://doi.org/10.1093/cybsec/tyy001.  
7.) Rahman, M. (2018, April 4). Amidst data scandal, Facebook will voluntarily enforce EU's new privacy rules "everywhere". XDA Developers. Retrieved November 21, 2021, from https://www.xda-developers.com/facebook-voluntarly-enforce-eu-privacy-law/.
