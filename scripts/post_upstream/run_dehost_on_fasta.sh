resolve_host_index() {
    case "${HOST_DB}" in
        dog)
            HOST_INDEX="/home/adprc/host_genome/dog_genome/host_genome_index"
            ;;
        cat)
            HOST_INDEX="/home/adprc/host_genome/cat_genome/host_genome_index"
            ;;
        human)
            HOST_INDEX="/home/adprc/host_genome/human_genome/host_genome_index"
            ;;
        mouse)
            HOST_INDEX="/home/adprc/host_genome/mouse_genome/host_genome_index"
            ;;
        cattle)
            HOST_INDEX="/home/adprc/host_genome/cattle_genome/host_genome_index"
            ;;
        duck)
            HOST_INDEX="/home/adprc/host_genome/duck_genome/host_genome_index"
            ;;
        goat)
            HOST_INDEX="/home/adprc/host_genome/goat_genome/host_genome_index"
            ;;
        horse)
            HOST_INDEX="/home/adprc/host_genome/horse_genome/host_genome_index"
            ;;
        pig)
            HOST_INDEX="/home/adprc/host_genome/pig_genome/host_genome_index"
            ;;
        chicken)
            HOST_INDEX="/home/adprc/host_genome/chicken_genome/host_genome_index"
            ;;
        rabbit)
            HOST_INDEX="/home/adprc/host_genome/rabbit_genome/host_genome_index"
            ;;
        sheep)
            HOST_INDEX="/home/adprc/host_genome/sheep_genome/host_genome_index"
            ;;
        turkey)
            HOST_INDEX="/home/adprc/host_genome/turkey_genome/host_genome_index"
            ;;
        *)
            echo "[ERROR] 不支援的 HOST_DB: ${HOST_DB}"
            echo "[ERROR] 目前支援：dog / cat / human / mouse / cattle / duck / goat / horse / pig / chicken / rabbit / sheep / turkey"
            exit 1
            ;;
    esac
}
