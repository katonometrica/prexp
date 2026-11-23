# the shipped migration files never change once released (no database)

    Code
      cat(paste(files$file, files$checksum), sep = "\n")
    Output
      001_schemas.sql fec1523f1ce7daca4ed590ba45c9ee6588c6012355635dab486a5f2b17ae9064
      002_dimensions.sql 9335126fcec842c9c826b5023ae7979afb894d7c6eb8103ebdb3362d45f98a2c
      003_fact.sql 9c2f0d530b5097fe1429c195f1df9bde0aef7105ef37f3f2c730598f25bf9a38
      004_rollups.sql b1ba15c76a3d5e5218dd578e4cfa7850be4e15d30b315818b7ef4fa06b44e1d7
      005_load_log.sql e04d293908922a123e78788b81f8497010d9c712904218300d2b6d98d0f8025e
      006_staging.sql 65aa39b0e49cf3330382022327c771610809e9df4c11d19ad472ed48928c2291
      007_app_views.sql 87264c12caf741bd56203b4708ff50c4b75555e02d5c823abe46055e4d31872f

