module Users::SessionsHelper
  RANDOM_NPC_EMAILS = %w[
    raubahn@syndicate.uldah.gov
    mbloefhiswyn@lanoscea.gov
    kan.e.senna@gridania.gov
    zenos@royal.garlemald.mil
    fleveilleur@sharlayan.edu
    warrioroflight@eorzeamail.com
    godbert@goldsaucer.net
    tataru@seventhdawn.org
    this.is.thancred@lnkprl.com
    cid@garlondironworks.com
    wanderingminstrel@orchestri.on
    starboard@omega.ai
    larboard@omega.ai
    securingway@carrot.moon
    conjuringcatgirl@aether.net
    koana.h@studium.sharlayan.edu
    thirdpromise@tour.tural
    delion@thavnairiantruth.info
    aid:msg:gov/sphene
    aid:msg:gov/knighthood/o.velona
  ].freeze

  def eegg_random_npc_email
    RANDOM_NPC_EMAILS.sample
  end
end
